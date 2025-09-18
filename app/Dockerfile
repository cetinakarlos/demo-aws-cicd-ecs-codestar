FROM public.ecr.aws/docker/library/node:20-alpine
WORKDIR /app
COPY package.json ./
RUN npm ci || npm i --omit=dev
COPY . .
EXPOSE 3000
CMD ["npm","start"]
