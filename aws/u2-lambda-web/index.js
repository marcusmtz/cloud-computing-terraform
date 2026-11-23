exports.handler = async () => ({
  statusCode: 200,
  headers: { "content-type": "text/html; charset=utf-8", "cache-control": "no-store" },
  body: "<!doctype html><html lang=\"es\"><meta charset=\"utf-8\"><title>NORCOM Cloud U2</title><body><h1>NORCOM Cloud U2</h1><p>Aplicación web de prueba de Lambda para la Unidad 2.</p><p>No procesa datos personales.</p></body></html>"
});
