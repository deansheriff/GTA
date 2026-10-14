# Naija Street Life server: API + realtime (WebSockets) for the Android game.
# Deployed on the owner's Coolify behind Cloudflare (docs/COOLIFY.md).
FROM node:22-bookworm-slim AS build
WORKDIR /build
COPY package.json package-lock.json ./
COPY apps/server/package.json apps/server/package.json
RUN npm ci --workspace @nsl/server --include-workspace-root=false --no-fund --no-audit
COPY tsconfig.base.json ./
COPY apps/server/tsconfig.json apps/server/tsconfig.json
COPY apps/server/src apps/server/src
RUN npm run build -w @nsl/server && npm prune --omit=dev --workspace @nsl/server --include-workspace-root=false

FROM node:22-bookworm-slim AS runtime
ENV NODE_ENV=production HOST=0.0.0.0 PORT=8787
WORKDIR /app
COPY --from=build --chown=node:node /build/node_modules ./node_modules
COPY --from=build --chown=node:node /build/apps/server/dist ./dist
COPY --chown=node:node apps/server/package.json ./package.json
USER node
EXPOSE 8787
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:8787/api/health').then(r=>{if(!r.ok)process.exit(1)}).catch(()=>process.exit(1))"
CMD ["node", "dist/index.js"]
