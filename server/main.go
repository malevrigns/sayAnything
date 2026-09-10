package main

import (
	"context"
	"errors"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"
)

func main() {
	cfg := Config{DBPath: env("DB_PATH", "sayanything.db"), WebDir: env("WEB_DIR", "web"), DownloadDir: env("DOWNLOAD_DIR", "../dist"), MediaDir: os.Getenv("MEDIA_DIR"), AllowedOrigin: os.Getenv("ALLOWED_ORIGIN"), AdminToken: os.Getenv("ADMIN_TOKEN")}
	s, e := NewServer(cfg)
	if e != nil {
		log.Fatal(e)
	}
	defer s.Close()
	port := env("PORT", "8080")
	log.Printf("SayAnything listening on :%s", port)
	srv := &http.Server{Addr: ":" + port, Handler: s.Handler(), ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 2 * time.Minute, WriteTimeout: 2 * time.Minute, IdleTimeout: 60 * time.Second}
	stopCtx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	shutdownDone := make(chan struct{})
	go func() {
		<-stopCtx.Done()
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		if err := srv.Shutdown(ctx); err != nil {
			log.Printf("服务器关闭超时: %v", err)
		}
		close(shutdownDone)
	}()
	if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		log.Printf("服务器启动失败: %v", err)
		return
	}
	if stopCtx.Err() != nil {
		<-shutdownDone
	}
}
func env(k, d string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return d
}
