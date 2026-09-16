FROM node:22-alpine
WORKDIR /app
COPY package.json ./
RUN npm install --omit=dev
COPY src ./src
COPY data ./data
ENV PORT=8080 DB_PATH=/data/khata.db
VOLUME ["/data"]
EXPOSE 8080
CMD ["node", "src/index.js"]
