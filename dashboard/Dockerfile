FROM node:20-alpine AS builder
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM node:20-alpine
RUN addgroup -S app && adduser -S app -G app
WORKDIR /app

COPY --from=builder /app/build ./build
COPY --from=builder /app/package.json ./
COPY --from=builder --chown=app:app /app/node_modules ./node_modules

ENV HOST=0.0.0.0
ENV PORT=3000
ENV CLUSTER_API_URL=http://cluster:9094

USER app

EXPOSE 3000
CMD ["node", "build"]