package main

//go:generate -command yacc go tool yacc
//go:generate yacc -o kismet.go -p "kismet" kismet.y

import (
	"fmt"
	"log"
	"os"
	"os/user"
	"path/filepath"

	"github.com/peterh/liner"
)

var (
	history_log string
)

func main() {
	line := liner.NewLiner()
	defer line.Close()

	if usr, err := user.Current(); err == nil {
		history_log = usr.HomeDir + "/.local/share/kismet/history.log"
	} else {
		history_log = "/var/log/kismet/history.log"
	}
	if f, err := os.Open(history_log); err == nil {
		line.ReadHistory(f)
		f.Close()
	}

	fmt.Println(
		"Greetings, human! I am Kismet <3\n",
		"Input a roll and press ENTER.\n",
		"Exit with 'exit' or CTRL-D.")

L:
	for {
		if input, err := line.Prompt("$ "); err == nil {
			line.AppendHistory(input)
			fmt.Println(input)
		} else {
			break L
		}
	}

	// Save history
	if err := os.MkdirAll(filepath.Dir(history_log), 0770); err != nil {
		log.Print("Error making directory: ", err)
	}
	if f, err := os.Create(history_log); err != nil {
		log.Print("Error saving history: ", err)
	} else {
		line.WriteHistory(f)
		f.Close()
	}
}
