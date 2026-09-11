const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');

(async () => {
  const manifest = JSON.parse(fs.readFileSync(path.resolve(__dirname, '../dist/release-manifest.json'), 'utf8'));
  const origin = process.env.SITE_URL || 'http://localhost:8080';
  for (const file of manifest.files.filter((file) => /\.(apk|zip)$/.test(file.name))) {
    const response = await fetch(`${origin}/downloads/${encodeURIComponent(file.name)}`);
    assert.equal(response.status, 200, file.name);
    const hash = crypto.createHash('sha256');
    let bytes = 0;
    for await (const chunk of response.body) { bytes += chunk.length; hash.update(chunk); }
    assert.equal(bytes, file.bytes, `${file.name}: size mismatch`);
    assert.equal(hash.digest('hex'), file.sha256, `${file.name}: SHA-256 mismatch`);
    console.log(`PASS download: ${file.name} (${bytes} bytes)`);
  }
})().catch((error) => { console.error(error); process.exitCode = 1; });
