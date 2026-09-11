FROM golang:1.25-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY *.go ./
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /sayanything .

FROM alpine:3.22
RUN apk add --no-cache ffmpeg && addgroup -S app && adduser -S app -G app && mkdir -p /data /data/media /downloads && chown -R app:app /data /downloads
COPY --from=build /sayanything /app/sayanything
COPY web /app/web
ENV PORT=8080 DB_PATH=/data/sayanything.db MEDIA_DIR=/data/media WEB_DIR=/app/web DOWNLOAD_DIR=/downloads
VOLUME ["/data"]
USER app
EXPOSE 8080
WORKDIR /app
ENTRYPOINT ["/app/sayanything"]
