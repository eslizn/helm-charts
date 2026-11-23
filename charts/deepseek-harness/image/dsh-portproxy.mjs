#!/usr/bin/env node
/**
 * Loopback TCP proxy for `kubectl port-forward`.
 *
 * dsh binds one concrete address (the Pod IP) because it rejects wildcard
 * hosts. The kubelet's port-forward implementation dials localhost inside the
 * Pod's network namespace, so this proxy accepts 127.0.0.1/::1 on the same
 * port and splices the connection to dsh on the Pod IP. It is a byte pipe,
 * not an HTTP proxy: WebSocket upgrades and the Host/Origin fence see the
 * original bytes. Service and Ingress traffic never uses this path.
 *
 * Lives in the same container, started by dsh-entrypoint.sh in the
 * background. If it dies, port-forward stops working; the kubelet probes still
 * target dsh directly on the Pod IP and stay green, so restart the Pod.
 */

import net from 'node:net'

const port = Number(process.env.DSH_WEB_PORT ?? 3080)
const upstreamHost = process.env.POD_IP

if (!Number.isInteger(port) || port <= 0 || port > 65535) {
  console.error(`dsh-portproxy: invalid DSH_WEB_PORT ${JSON.stringify(process.env.DSH_WEB_PORT)}`)
  process.exit(1)
}
if (!upstreamHost) {
  console.error('dsh-portproxy: POD_IP is required')
  process.exit(1)
}

const servers = []

function splice(client) {
  const upstream = net.connect({ host: upstreamHost, port })
  const destroy = () => {
    client.destroy()
    upstream.destroy()
  }
  client.on('error', destroy)
  upstream.on('error', destroy)
  client.on('close', destroy)
  upstream.on('close', destroy)
  client.pipe(upstream).pipe(client)
}

for (const host of ['127.0.0.1', '::1']) {
  const server = net.createServer(splice)
  server.on('error', (error) => {
    // ::1 is optional; IPv4 loopback is what port-forward normally resolves.
    if (host === '::1' && (error.code === 'EADDRNOTAVAIL' || error.code === 'EAFNOSUPPORT')) {
      return
    }
    console.error(`dsh-portproxy: ${host}:${String(port)}: ${error.message}`)
    process.exit(1)
  })
  server.listen(port, host, () => {
    console.log(`dsh-portproxy: ${host}:${String(port)} -> ${upstreamHost}:${String(port)}`)
  })
  servers.push(server)
}

for (const signal of ['SIGINT', 'SIGTERM']) {
  process.on(signal, () => {
    for (const server of servers) {
      if (server.listening) server.close()
    }
    process.exit(0)
  })
}
