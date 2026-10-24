// The Claude connector's MCP probe (M16): talks to a Salesforce Hosted MCP server exactly as an MCP
// client does -- OAuth authorization code with PKCE, then initialize, tools/list, prompts/list and
// tools/call over Streamable HTTP -- so the gate can check the servers without a chat client.
//
//   node scripts/mcp-probe.mjs --server <mcp url> --instance <org url> --client-id <consumer key>
//        [--tool <name> --args '<json of one input>'] [--prompt <name>] [--quiet]
//
// The first run opens the browser once for the user to log in and allow access; the callback is
// http://localhost:1717/OauthRedirect, registered on the AMFClaudeConnector External Client App.
// Later runs reuse the saved refresh token in .mcp-probe/ (git-ignored), and keep the rotated
// replacement, because the app rotates refresh tokens.
//
// --args is ONE tool input; the probe wraps it as {"inputs": [ ... ]}, the shape every invocable
// Apex tool takes (technical log M16.1). Needs only Node 22's standard library.

import { createHash, randomBytes } from 'node:crypto';
import { createServer } from 'node:http';
import { mkdirSync, readFileSync, writeFileSync, existsSync } from 'node:fs';
import { spawn } from 'node:child_process';

const CALLBACK_PORT = 1717;
const REDIRECT_URI = `http://localhost:${CALLBACK_PORT}/OauthRedirect`;
const SCOPES = 'mcp_api refresh_token';
const PROTOCOL_VERSION = '2025-06-18';

const args = parseArgs(process.argv.slice(2));
const server = required('server');
const instance = required('instance').replace(/\/$/, '');
const clientId = args['client-id'] || process.env.SF_CONSUMER_KEY || fail('--client-id is required');

const cacheDir = '.mcp-probe';
const cacheFile = `${cacheDir}/token.${server.split('/').pop()}.json`;

const token = await accessToken();
const session = await initialize(token);

const tools = await rpc(token, session, 'tools/list', {});
log(`tools/list: ${tools.tools.length} tool(s)`);
for (const tool of tools.tools) {
    const hints = tool.annotations ?? {};
    log(`  - ${tool.name}  readOnly=${hints.readOnlyHint} destructive=${hints.destructiveHint} idempotent=${hints.idempotentHint} openWorld=${hints.openWorldHint}`);
}

try {
    const prompts = await rpc(token, session, 'prompts/list', {});
    log(`prompts/list: ${(prompts.prompts ?? []).length} prompt(s) ${(prompts.prompts ?? []).map((p) => p.name).join(', ')}`);
} catch (error) {
    log(`prompts/list: ${error.message}`);
}

if (args.prompt) {
    const got = await rpc(token, session, 'prompts/get', { name: args.prompt, arguments: {} });
    console.log(JSON.stringify(got, null, 2));
}

if (args.tool) {
    const input = args.args ? JSON.parse(args.args) : {};
    const called = await rpc(token, session, 'tools/call', { name: args.tool, arguments: { inputs: [input] } });
    console.log(JSON.stringify(called.structuredContent ?? called, null, 2));
    if (called.isError) process.exitCode = 1;
}

// ── MCP over Streamable HTTP ──────────────────────────────────────────────────

async function initialize(bearer) {
    const response = await post(bearer, null, {
        jsonrpc: '2.0',
        id: 1,
        method: 'initialize',
        params: { protocolVersion: PROTOCOL_VERSION, capabilities: {}, clientInfo: { name: 'amf-mcp-probe', version: '1.0.0' } }
    });
    const sessionId = response.headers.get('mcp-session-id');
    const result = await bodyOf(response);
    log(`initialize: ${result.result?.serverInfo?.name ?? '?'} ${result.result?.serverInfo?.version ?? ''}, protocol ${result.result?.protocolVersion}`);
    if (result.result?.instructions) log(`instructions: ${result.result.instructions}`);
    await post(bearer, sessionId, { jsonrpc: '2.0', method: 'notifications/initialized' });
    return sessionId;
}

let nextId = 2;
async function rpc(bearer, sessionId, method, params) {
    const response = await post(bearer, sessionId, { jsonrpc: '2.0', id: nextId++, method, params });
    const message = await bodyOf(response);
    if (message.error) throw new Error(`${method}: ${message.error.code} ${message.error.message}`);
    return message.result;
}

async function post(bearer, sessionId, payload) {
    const headers = {
        Authorization: `Bearer ${bearer}`,
        'Content-Type': 'application/json',
        Accept: 'application/json, text/event-stream',
        'MCP-Protocol-Version': PROTOCOL_VERSION
    };
    if (sessionId) headers['Mcp-Session-Id'] = sessionId;
    const response = await fetch(server, { method: 'POST', headers, body: JSON.stringify(payload) });
    if (!response.ok && response.status !== 202) {
        throw new Error(`${payload.method}: HTTP ${response.status} ${await response.text()}`);
    }
    return response;
}

async function bodyOf(response) {
    const text = await response.text();
    if (!(response.headers.get('content-type') ?? '').includes('text/event-stream')) {
        return JSON.parse(text);
    }
    // One JSON-RPC message per SSE event; the answer is the last data line.
    const data = text.split(/\r?\n/).filter((line) => line.startsWith('data:')).map((line) => line.slice(5).trim());
    return JSON.parse(data[data.length - 1]);
}

// ── OAuth: authorization code with PKCE, refresh token kept and rotated ───────

async function accessToken() {
    if (existsSync(cacheFile)) {
        const cached = JSON.parse(readFileSync(cacheFile, 'utf8'));
        const refreshed = await tokenRequest({ grant_type: 'refresh_token', refresh_token: cached.refresh_token, client_id: clientId });
        if (refreshed.access_token) {
            save({ ...cached, ...refreshed });
            log('auth: reused the saved refresh token, no login needed');
            return refreshed.access_token;
        }
        log(`auth: saved refresh token refused (${refreshed.error}); logging in again`);
    }

    const verifier = randomBytes(48).toString('base64url');
    const challenge = createHash('sha256').update(verifier).digest('base64url');
    const state = randomBytes(16).toString('hex');
    const authorize =
        `${instance}/services/oauth2/authorize?response_type=code` +
        `&client_id=${encodeURIComponent(clientId)}&redirect_uri=${encodeURIComponent(REDIRECT_URI)}` +
        `&scope=${encodeURIComponent(SCOPES)}&code_challenge=${challenge}&code_challenge_method=S256&state=${state}`;

    const code = await new Promise((resolve, reject) => {
        const listener = createServer((request, reply) => {
            const url = new URL(request.url, REDIRECT_URI);
            if (url.pathname !== '/OauthRedirect') return reply.writeHead(404).end();
            const error = url.searchParams.get('error');
            reply.writeHead(200, { 'Content-Type': 'text/plain' }).end(error ? `Login failed: ${error}` : 'Logged in. You can close this tab.');
            listener.close();
            if (error) return reject(new Error(`${error}: ${url.searchParams.get('error_description')}`));
            if (url.searchParams.get('state') !== state) return reject(new Error('state mismatch'));
            resolve(url.searchParams.get('code'));
        });
        listener.listen(CALLBACK_PORT, () => {
            log(`auth: log in and allow access in the browser. If it does not open, visit:\n${authorize}`);
            open(authorize);
        });
    });

    const issued = await tokenRequest({
        grant_type: 'authorization_code',
        code,
        client_id: clientId,
        redirect_uri: REDIRECT_URI,
        code_verifier: verifier
    });
    if (!issued.access_token) fail(`token exchange failed: ${JSON.stringify(issued)}`);
    save(issued);
    log('auth: logged in, token saved');
    return issued.access_token;
}

async function tokenRequest(form) {
    const response = await fetch(`${instance}/services/oauth2/token`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams(form)
    });
    return response.json();
}

function save(tokens) {
    mkdirSync(cacheDir, { recursive: true });
    writeFileSync(cacheFile, JSON.stringify(tokens, null, 2));
}

function open(url) {
    const opener = process.platform === 'win32'
        ? spawn('rundll32', ['url.dll,FileProtocolHandler', url], { detached: true, stdio: 'ignore' })
        : spawn(process.platform === 'darwin' ? 'open' : 'xdg-open', [url], { detached: true, stdio: 'ignore' });
    opener.on('error', () => {});
    opener.unref();
}

// ── Small helpers ─────────────────────────────────────────────────────────────

function parseArgs(argv) {
    const parsed = {};
    for (let i = 0; i < argv.length; i++) {
        if (!argv[i].startsWith('--')) continue;
        const name = argv[i].slice(2);
        parsed[name] = argv[i + 1] && !argv[i + 1].startsWith('--') ? argv[++i] : true;
    }
    return parsed;
}

function required(name) {
    return args[name] || fail(`--${name} is required`);
}

function log(message) {
    if (!args.quiet) console.error(message);
}

function fail(message) {
    console.error(message);
    process.exit(2);
}
