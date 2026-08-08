// 联调脚本：验证 WebSocket 握手和二进制帧（不依赖浏览器）。
// 用法：先启动 `vibepilot --demo --port 8090`，再运行 `node scripts/ws-test.js 8090`
const net = require('net');
const crypto = require('crypto');

const port = Number(process.argv[2] || 8090);
const key = crypto.randomBytes(16).toString('base64');
const sock = net.connect(port, '127.0.0.1');
let handshaken = false;
let buf = Buffer.alloc(0);
let frames = 0;

sock.on('connect', () => {
  console.log('[connect] 已连接，发送 WebSocket 升级请求');
  const req =
    `GET /stream HTTP/1.1\r\nHost: 127.0.0.1:${port}\r\n` +
    `Upgrade: websocket\r\nConnection: Upgrade\r\n` +
    `Sec-WebSocket-Key: ${key}\r\nSec-WebSocket-Version: 13\r\n\r\n`;
  console.log('[request] 字节数 =', Buffer.byteLength(req));
  sock.write(req, () => console.log('[write] 完成'));
});

sock.on('data', (d) => {
  try {
    buf = Buffer.concat([buf, d]);
    if (!handshaken) {
      const idx = buf.indexOf('\r\n\r\n');
      if (idx < 0) return;
      const head = buf.slice(0, idx).toString();
      console.log('HTTP:', head.split('\r\n')[0]);
      console.log('Upgrade 成功:', head.includes('101 Switching Protocols'));
      handshaken = true;
      buf = buf.slice(idx + 4);
    }

    while (buf.length >= 2) {
      const b0 = buf[0];
      let payloadLen = buf[1] & 0x7f;
      let headerLen = 2;
      if (payloadLen === 126) {
        if (buf.length < 4) return;
        payloadLen = buf.readUInt16BE(2);
        headerLen = 4;
      } else if (payloadLen === 127) {
        if (buf.length < 10) return;
        payloadLen = Number(buf.readBigUInt64BE(2));
        headerLen = 10;
      }
      if (buf.length < headerLen + payloadLen) return;
      const payload = buf.slice(headerLen, headerLen + payloadLen);
      const isJpeg = payload.length > 2 && payload[0] === 0xff && payload[1] === 0xd8;
      console.log(`帧 #${frames + 1}: opcode=${b0 & 0x0f} bytes=${payload.length} jpeg=${isJpeg}`);
      frames += 1;
      buf = buf.slice(headerLen + payloadLen);
      if (frames >= 3) {
        console.log('OK：收到 3 帧，推流链路正常');
        process.exit(0);
      }
    }
  } catch (err) {
    console.error('解析出错：', err.message, err.stack);
    process.exit(1);
  }
});

sock.on('error', (e) => { console.error('连接错误:', e.message); process.exit(1); });
setTimeout(() => { console.error('超时，未收到足够帧'); process.exit(1); }, 10000);
