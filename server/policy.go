package main

import "net/http"

// These definitions are shared by public input hints and authoritative writes.
const (
	maxPostCharacters    = 1000
	maxMessageCharacters = 2000
	maxCampusCharacters  = 80
	maxAliasCharacters   = 40
	maxAttachments       = 4
	maxImageBytes        = int64(10 << 20)
	maxVideoBytes        = int64(50 << 20)
	maxTotalBytes        = int64(50 << 20)
)

var postCategories = []string{"校园日常", "心事树洞", "搭子集合", "恋爱碎碎念", "学习交流"}

type mediaFormat struct {
	kind, mime string
	extensions []string
}

var mediaFormats = []mediaFormat{
	{"image", "image/jpeg", []string{"jpg", "jpeg"}},
	{"image", "image/png", []string{"png"}},
	{"image", "image/webp", []string{"webp"}},
	{"video", "video/mp4", []string{"mp4"}},
	{"video", "video/webm", []string{"webm"}},
}

func detectMediaFormat(data []byte) mediaFormat {
	mime := http.DetectContentType(data)
	for _, format := range mediaFormats {
		if format.kind == "image" && format.mime == mime ||
			format.mime == "video/mp4" && isMP4(data) ||
			format.mime == "video/webm" && isWebM(data) {
			return format
		}
	}
	return mediaFormat{}
}

func (s *Server) policy(w http.ResponseWriter, r *http.Request) {
	images, videos := []string{}, []string{}
	for _, format := range mediaFormats {
		if format.kind == "image" {
			images = append(images, format.extensions...)
		} else {
			videos = append(videos, format.extensions...)
		}
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"categories": postCategories,
		"limits":     map[string]int{"postCharacters": maxPostCharacters, "messageCharacters": maxMessageCharacters, "campusCharacters": maxCampusCharacters, "aliasCharacters": maxAliasCharacters},
		"media":      map[string]any{"maxAttachments": maxAttachments, "maxImageBytes": maxImageBytes, "maxVideoBytes": maxVideoBytes, "maxTotalBytes": maxTotalBytes, "imageExtensions": images, "videoExtensions": videos},
	})
}
