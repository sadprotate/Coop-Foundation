FROM node:24-alpine
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --ignore-scripts
COPY server.mjs combat.mjs match.mjs ./
USER node
ENV NODE_ENV=production
ENV PORT=8787
EXPOSE 8787
CMD ["node", "server.mjs"]
