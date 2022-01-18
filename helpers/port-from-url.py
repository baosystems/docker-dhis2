#!/usr/bin/env python3

import sys
from urllib.parse import urlparse

# First argument is the URL
try:
    url = sys.argv[1]
except IndexError:
    print('[ERROR] Missing argument', file=sys.stderr)
    sys.exit(1)

parsed = urlparse(url)

# See list at https://docs.python.org/3.9/library/urllib.parse.html
valid_protos = ('file', 'ftp', 'gopher', 'hdl', 'http', 'https', 'imap', 'mailto', 'mms', 'news', 'nntp', 'prospero', 'rsync', 'rtsp', 'rtspu', 'sftp', 'shttp', 'sip', 'sips', 'snews', 'svn', 'svn+ssh', 'telnet', 'wais', 'ws', 'wss', )

# Add "http://" to URL if no scheme provided
if parsed.scheme not in valid_protos:
    parsed = urlparse(f'http://{url}')

# With scheme of http or https, use default port if one is not provided
if parsed.port == None:
    if parsed.scheme == 'https':
        port = 443
    elif parsed.scheme == 'http':
        port = 80
else:
    port = parsed.port

print(port)
