// live-poll-app
//
// A small real-time polling app. It exists to demonstrate one thing
// clearly: how a pod running on EKS ends up with a database password
// without that password ever passing through GitHub Actions or being
// committed to git.
//
// The password arrives here purely as the environment variable
// DB_PASSWORD, which Kubernetes populates from a Secret named
// "app-db-credentials". That Secret is not created by this app, by
// Terraform, or by ArgoCD directly — it is created at runtime inside
// the cluster by the External Secrets Operator, which reads the real
// value from AWS Secrets Manager using the pod's own IRSA identity.
// See the README section "Secret Management: Terraform vs GitHub
// Actions vs ArgoCD" for the full path end to end.

const express = require("express");
const http = require("http");
const { WebSocketServer } = require("ws");
const mysql = require("mysql2/promise");

const PORT = process.env.PORT || 3000;

const DB_CONFIG = {
  host: process.env.DB_HOST,
  port: process.env.DB_PORT || 3306,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME,
  waitForConnections: true,
  connectionLimit: 5,
};

const app = express();
app.use(express.json());
app.use(express.static("public"));

const server = http.createServer(app);
const wss = new WebSocketServer({ server, path: "/ws" });

let pool;

async function initDb() {
  pool = mysql.createPool(DB_CONFIG);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS poll_options (
      id INT AUTO_INCREMENT PRIMARY KEY,
      label VARCHAR(255) NOT NULL,
      votes INT NOT NULL DEFAULT 0
    )
  `);

  const [rows] = await pool.query("SELECT COUNT(*) AS count FROM poll_options");
  if (rows[0].count === 0) {
    await pool.query(
      "INSERT INTO poll_options (label, votes) VALUES (?, 0), (?, 0), (?, 0)",
      ["AWS", "GCP", "Azure"]
    );
  }
}

function broadcast(payload) {
  const message = JSON.stringify(payload);
  wss.clients.forEach((client) => {
    if (client.readyState === client.OPEN) {
      client.send(message);
    }
  });
}

app.get("/healthz", (req, res) => {
  res.json({ status: "ok" });
});

app.get("/api/results", async (req, res) => {
  const [rows] = await pool.query("SELECT id, label, votes FROM poll_options ORDER BY id");
  res.json(rows);
});

app.post("/api/vote/:id", async (req, res) => {
  const { id } = req.params;

  await pool.query("UPDATE poll_options SET votes = votes + 1 WHERE id = ?", [id]);

  const [rows] = await pool.query("SELECT id, label, votes FROM poll_options ORDER BY id");

  // This is the "real-time" part — every connected browser gets the
  // updated tally immediately over the WebSocket, without polling.
  broadcast({ type: "results", data: rows });

  res.json({ ok: true });
});

wss.on("connection", async (ws) => {
  const [rows] = await pool.query("SELECT id, label, votes FROM poll_options ORDER BY id");
  ws.send(JSON.stringify({ type: "results", data: rows }));
});

initDb()
  .then(() => {
    server.listen(PORT, () => {
      console.log(`live-poll-app listening on port ${PORT}`);
    });
  })
  .catch((err) => {
    console.error("Failed to initialize database:", err);
    process.exit(1);
  });
