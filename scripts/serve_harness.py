import http.server,urllib.request,urllib.error,functools
class Handler(http.server.SimpleHTTPRequestHandler):
 def log_message(self,*args):pass
 def do_GET(self):
  if self.path.startswith('/ELPSY/api/'):return self.proxy()
  return super().do_GET()
 def proxy(self):
  body=self.rfile.read(int(self.headers.get('Content-Length','0'))) or None
  headers={k:v for k,v in self.headers.items() if k.lower() not in ('connection','content-length','accept-encoding')}
  req=urllib.request.Request('http://127.0.0.1:29092'+self.path,data=body,method=self.command,headers=headers)
  try:r=urllib.request.build_opener(urllib.request.ProxyHandler({})).open(req,timeout=25)
  except urllib.error.HTTPError as e:r=e
  self.send_response(r.status)
  for k,v in r.headers.items():
   if k.lower() not in ('connection','transfer-encoding','content-length'):self.send_header(k,v)
  data=r.read();self.send_header('Content-Length',str(len(data)));self.end_headers();self.wfile.write(data)
 do_POST=do_PUT=do_PATCH=do_DELETE=do_OPTIONS=proxy
http.server.ThreadingHTTPServer(('127.0.0.1',25178),functools.partial(Handler,directory=str(__import__('pathlib').Path(__file__).resolve().parents[1] / 'build/web'))).serve_forever()
