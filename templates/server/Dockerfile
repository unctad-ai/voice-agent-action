FROM node:22-slim
WORKDIR /app
COPY package.json package-lock.json* ./
# Cache-bust npm install when "latest" packages have new versions
ARG NPM_CACHE_BUST=0
RUN npm install --legacy-peer-deps
COPY . .
EXPOSE 3001
CMD ["npx", "tsx", "index.ts"]
