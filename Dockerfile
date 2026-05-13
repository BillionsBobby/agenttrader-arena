# ── Base: pnpm + system deps ──
FROM node:20-alpine AS base

RUN apk add --no-cache libc6-compat && \
    corepack enable && \
    corepack prepare pnpm@10.29.3 --activate

ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"
WORKDIR /repo

# ── Deps: workspace package manifests (cached layer) ──
FROM base AS deps

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY apps/web-new/package.json ./apps/web-new/package.json
COPY apps/workers/package.json ./apps/workers/package.json
COPY packages/agenttrader-types/package.json ./packages/agenttrader-types/package.json

# ── Web builder ──
FROM deps AS web-builder

ARG NEXT_PUBLIC_APP_URL
ARG AUTH_URL
ENV NEXT_PUBLIC_APP_URL=$NEXT_PUBLIC_APP_URL
ENV AUTH_URL=$AUTH_URL

RUN pnpm --filter web-new... fetch --frozen-lockfile

COPY apps/web-new ./apps/web-new
COPY packages/agenttrader-types ./packages/agenttrader-types

RUN pnpm --filter web-new... install --offline --frozen-lockfile
RUN pnpm --filter web-new build

# ── Web runner (production) ──
FROM base AS web-runner

WORKDIR /app

RUN addgroup --system --gid 1001 nodejs && \
    adduser --system --uid 1001 nextjs

COPY --from=web-builder /repo/apps/web-new/.next/standalone ./
COPY --from=web-builder /repo/apps/web-new/public ./apps/web-new/public
COPY --from=web-builder --chown=nextjs:nodejs /repo/apps/web-new/.next/static ./apps/web-new/.next/static

USER nextjs

EXPOSE 8080

ENV NODE_ENV=production
ENV HOSTNAME=0.0.0.0
ENV PORT=8080

CMD ["node", "apps/web-new/server.js"]

# ── Worker ──
FROM deps AS worker

RUN pnpm --filter agenttrader-market-ws... fetch --frozen-lockfile

COPY apps/workers ./apps/workers
COPY packages/agenttrader-types ./packages/agenttrader-types

RUN pnpm --filter agenttrader-market-ws... install --offline --frozen-lockfile

EXPOSE 8080

CMD ["pnpm", "--filter", "agenttrader-market-ws", "start"]
