package main

import (
	"bufio"
	"encoding/binary"
	"encoding/json"
	"io"
	"os"
)

type request struct {
	Action  string `json:"action"`
	Path    string `json:"path"`
	Content string `json:"content,omitempty"`
}

type response struct {
	Success bool   `json:"success,omitempty"`
	Content string `json:"content,omitempty"`
	Mtime   int64  `json:"mtime,omitempty"`
	Error   string `json:"error,omitempty"`
}

func main() {
	in := bufio.NewReader(os.Stdin)
	for {
		req, err := readMessage(in)
		if err != nil {
			if err == io.EOF {
				return
			}
			return
		}

		var msg request
		if err := json.Unmarshal(req, &msg); err != nil {
			_ = writeMessage(os.Stdout, response{Error: err.Error()})
			continue
		}

		res := handle(msg)
		_ = writeMessage(os.Stdout, res)
	}
}

func handle(msg request) response {
	switch msg.Action {
	case "read":
		data, mtime, err := readFile(msg.Path)
		if err != nil {
			return response{Error: err.Error()}
		}
		return response{Success: true, Content: string(data), Mtime: mtime}
	case "save":
		mtime, err := saveFile(msg.Path, []byte(msg.Content))
		if err != nil {
			return response{Error: err.Error()}
		}
		return response{Success: true, Mtime: mtime}
	case "stat":
		mtime, err := statFile(msg.Path)
		if err != nil {
			return response{Error: err.Error()}
		}
		return response{Success: true, Mtime: mtime}
	default:
		return response{Error: "unknown action"}
	}
}

func readFile(path string) ([]byte, int64, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, 0, err
	}
	mtime, err := statFile(path)
	if err != nil {
		return nil, 0, err
	}
	return data, mtime, nil
}

func saveFile(path string, data []byte) (int64, error) {
	mode := os.FileMode(0644)
	if info, err := os.Stat(path); err == nil {
		mode = info.Mode().Perm()
	}
	if err := os.WriteFile(path, data, mode); err != nil {
		return 0, err
	}
	return statFile(path)
}

func statFile(path string) (int64, error) {
	info, err := os.Stat(path)
	if err != nil {
		return 0, err
	}
	return info.ModTime().UnixMilli(), nil
}

func readMessage(r io.Reader) ([]byte, error) {
	var sizeBuf [4]byte
	if _, err := io.ReadFull(r, sizeBuf[:]); err != nil {
		return nil, err
	}
	size := binary.LittleEndian.Uint32(sizeBuf[:])
	buf := make([]byte, size)
	if _, err := io.ReadFull(r, buf); err != nil {
		return nil, err
	}
	return buf, nil
}

func writeMessage(w io.Writer, msg response) error {
	data, err := json.Marshal(msg)
	if err != nil {
		return err
	}
	var sizeBuf [4]byte
	binary.LittleEndian.PutUint32(sizeBuf[:], uint32(len(data)))
	if _, err := w.Write(sizeBuf[:]); err != nil {
		return err
	}
	_, err = w.Write(data)
	return err
}
