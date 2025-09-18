const http = require("http");
const port = process.env.PORT || 3000;
const msg = process.env.APP_MESSAGE || "Hello from Kode-Soul DevOps Tools!";
const server = http.createServer((req, res) => {
  res.writeHead(200, {"Content-Type": "application/json"});
  res.end(JSON.stringify({ ok: true, msg, time: new Date().toISOString() }));
});
server.listen(port, () => console.log(`Listening on :${port}`));
