# syntax=docker/dockerfile:1
# =================================================================
# INSTALL IMAGE
#           use the official Bun image
#           see all versions at https://hub.docker.com/r/oven/bun/tags
# =================================================================
FROM oven/bun:1 as base
# Install openssl for Prisma
RUN apt update && apt install -y --no-install-recommends dumb-init openssl sqlite3 

WORKDIR /usr/src/app

# =================================================================
# ENVIRONMENT SETUP
#           install dependencies into temp directory
#           this will cache them and speed up future builds
# =================================================================
FROM base AS install
RUN mkdir -p /temp/{dev,prod}
COPY --chown=bun:bun package.json bun.lockb /temp/dev/
RUN cd /temp/dev && bun install --frozen-lockfile

# install with --production (exclude devDependencies)
COPY --chown=bun:bun package.json bun.lockb /temp/prod/
RUN cd /temp/prod && bun install --frozen-lockfile --production

# =================================================================
# PRE_RELEASE / TESTING / BUILD
#           copy node_modules from temp directory
#           then copy all (non-ignored) project files into the image
# =================================================================
FROM base AS prerelease
COPY --chown=bun:bun --from=install /temp/dev/node_modules node_modules
COPY --chown=bun:bun . .
ADD prisma .

# [optional] tests & build
ENV NODE_ENV=production
RUN bun test
RUN bun run build
RUN bun prisma generate
RUN bun run build
# =================================================================
# RELEASE
#           copy production dependencies and source code into final image
# =================================================================
FROM base AS release
ENV DATABASE_URL=file:/data/sqlite.db?connection_limit=1
ENV PORT="3000"
ENV NODE_ENV="production"
# add shortcut for connecting to database CLI
RUN echo "#!/bin/sh\nset -x\nsqlite3 \$DATABASE_URL" > /usr/local/bin/database-cli && chmod +x /usr/local/bin/database-cli

COPY --chown=bun:bun --from=install /temp/prod/node_modules node_modules
# COPY --chown=bun:bun --from=prerelease /usr/src/app/index.ts .
COPY --chown=bun:bun --from=prerelease /usr/src/app/package.json .
copy --chown=bun:bun --from=prerelease /usr/src/app/node_modules/.prisma .
copy --chown=bun:bun --from=prerelease  /usr/src/app/server.ts .
copy --chown=bun:bun --from=prerelease  /usr/src/app/start.sh .
copy --chown=bun:bun --from=prerelease  /usr/src/app/build .
copy --chown=bun:bun --from=prerelease  /usr/src/app/public .
copy --chown=bun:bun --from=prerelease  /usr/src/app/prisma .
# =================================================================
# INIT / START
#           run the app
# =================================================================

USER bun
EXPOSE 3000/tcp
ENTRYPOINT [ "dumb-init", "bun", "run", "server.ts" ]