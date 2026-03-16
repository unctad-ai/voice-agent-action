# check=skip=SecretsUsedInArgOrEnv
FROM node:22-slim AS frontend
WORKDIR /app
COPY package.json package-lock.json* ./
ARG NPM_CACHE_BUST=0
RUN npm install --legacy-peer-deps
COPY . .
ARG VITE_BACKEND_URL
ARG VITE_API_KEY
ARG VITE_COPILOT_NAME
RUN printf 'VITE_BACKEND_URL=%s\nVITE_API_KEY=%s\nVITE_COPILOT_NAME=%s\n' \
    "${VITE_BACKEND_URL}" "${VITE_API_KEY}" "${VITE_COPILOT_NAME}" > .env.production \
    && npx vite build

FROM node:22-slim
WORKDIR /app
COPY server/package.json server/package-lock.json* ./
ARG NPM_CACHE_BUST=0
RUN npm install --legacy-peer-deps
COPY server/ .
COPY --from=frontend /app/build ./build
EXPOSE 80
CMD ["npx", "tsx", "index.ts"]
