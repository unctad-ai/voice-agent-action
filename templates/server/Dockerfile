FROM node:22-slim
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm install --legacy-peer-deps
COPY . .
EXPOSE 3001
CMD ["npx", "tsx", "index.ts"]
