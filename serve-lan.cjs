const http = require('node:http');
const { createReadStream } = require('node:fs');
const { open, readFile } = require('node:fs/promises');
const { createHash } = require('node:crypto');
const { networkInterfaces } = require('node:os');
const { join } = require('node:path');
const { pipeline } = require('node:stream/promises');

const port = 8000;
const filename = 'Stomp and Scurry - LAN.exe';
const downloadPath = `/${encodeURIComponent(filename)}`;
const launcherName = 'Stomp and Scurry Launcher - LAN.exe';
const launcherManifestPath = '/launcher-release.json';
const files = new Map([
    ['/launcher.exe', launcherName],
    ['/game.exe', filename],
    [downloadPath, filename],
]);

async function sha256(path) {
    const hash = createHash('sha256');
    for await (const chunk of createReadStream(path)) {
        hash.update(chunk);
    }
    return hash.digest('hex');
}

async function loadLauncherRelease() {
    const manifest = JSON.parse(await readFile(join(__dirname, 'build', 'launcher-release.json'), 'utf8'));
    if (!Number.isInteger(manifest.launcher_version) || manifest.launcher_version < 1 ||
        typeof manifest.launcher_hash !== 'string' || !/^[a-f0-9]{64}$/.test(manifest.launcher_hash)) {
        throw new Error('launcher-release.json has no valid launcher version and SHA-256.');
    }
    const launcherPath = join(__dirname, 'build', launcherName);
    const actualHash = await sha256(launcherPath);
    if (actualHash !== manifest.launcher_hash) {
        throw new Error(`The launcher does not match launcher-release.json (expected ${manifest.launcher_hash}, found ${actualHash}).`);
    }
    return {
        version: manifest.launcher_version,
        hash: actualHash,
        publicManifest: JSON.stringify({
            launcher_version: manifest.launcher_version,
            launcher_hash: actualHash,
            launcher_download: '/launcher.exe',
        }),
    };
}

async function main() {
const launcherRelease = await loadLauncherRelease();
const server = http.createServer(async (request, response) => {
    if (request.method !== 'GET' && request.method !== 'HEAD') {
        response.writeHead(405, { Allow: 'GET, HEAD' }).end();
        return;
    }
    if (request.url === '/') {
        const page = '<!doctype html><meta charset="utf-8"><title>Stomp &amp; Scurry</title>' +
            `<h1>Stomp &amp; Scurry</h1><p><a href="/launcher.exe">Download the self-updating Windows launcher (version ${launcherRelease.version})</a></p>` +
            '<p>The launcher checks for updates when joining a host.</p>' +
            '<p><a href="/game.exe">Download the game executable</a></p>';
        response.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
        response.end(request.method === 'HEAD' ? undefined : page);
        return;
    }
    if (request.url === launcherManifestPath) {
        const body = launcherRelease.publicManifest;
        response.writeHead(200, {
            'Content-Type': 'application/json; charset=utf-8',
            'Content-Length': Buffer.byteLength(body),
            'Cache-Control': 'no-store',
        });
        response.end(request.method === 'HEAD' ? undefined : body);
        return;
    }
    const downloadName = files.get(request.url);
    if (!downloadName) {
        response.writeHead(404).end('File not found.');
        return;
    }

    let file;
    try {
        file = await open(join(__dirname, 'build', downloadName), 'r');
        const { size } = await file.stat();
        response.writeHead(200, {
            'Content-Type': 'application/octet-stream',
            'Content-Disposition': `attachment; filename="${downloadName}"`,
            'Content-Length': size,
        });
        if (request.method === 'HEAD') {
            response.end();
        } else {
            await pipeline(file.createReadStream(), response);
        }
    } catch (error) {
        if (error.code !== 'ERR_STREAM_PREMATURE_CLOSE') {
            console.error(error.message);
        }
        if (!response.headersSent) {
            response.writeHead(error.code === 'ENOENT' ? 404 : 500).end('Game download unavailable.');
        } else if (!response.writableFinished) {
            response.destroy();
        }
    } finally {
        await file?.close();
    }
});

server.on('error', (error) => {
    console.error(`Could not start the server on port ${port}. ${error.message}`);
    process.exitCode = 1;
});

server.listen(port, '0.0.0.0', () => {
    console.log('Share the address for your Wi-Fi or Ethernet adapter.');
    for (const [adapter, addresses] of Object.entries(networkInterfaces())) {
        for (const address of addresses) {
            if (address.family === 'IPv4' && !address.internal) {
                console.log(`${adapter}  http://${address.address}:${port}/`);
            }
        }
    }
    console.log(`Serving self-updating launcher version ${launcherRelease.version} at /launcher.exe (SHA-256 ${launcherRelease.hash}).`);
    console.log('Press Ctrl+C to stop before hosting from the launcher.');
});
}

main().catch((error) => {
    console.error(`Could not prepare the launcher download. ${error.message}`);
    process.exitCode = 1;
});
