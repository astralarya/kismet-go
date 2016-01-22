%{

package main

import (
	"bytes"
	"log"
	"unicode/utf8"
	"unicode"
	"strings"
	"strconv"
)

type numstring struct {
	Num *big.Rat
	String string
}

%}

%union {
	word string
	num numstring
}

%type	<word>	word

%left AND OR
%right NOT
%left EQ NE LT GT LE GE
%nonassoc '(' ')'

%token	<num>	NUM
%token	<word>	WORD
%token	ERROR

%%

top:
	directive
	{
		querylex.(*queryLex).Out.Query = $1
	}

word:
	WORD
	{
		$$ = $1
	}
|	word NUM
	{
		$$ = strings.Join([]string{$1,$2.String}, " ")
	}
|	word WORD
	{
		$$ = strings.Join([]string{$1,$2}, " ")
	}
%%

// The parser expects the lexer to return 0 on EOF.  Give it a name
// for clarity.
const eof = 0

// The parser uses the type <prefix>Lex as a lexer.  It must provide
// the methods Lex(*<prefix>SymType) int and Error(string).
type queryLex struct {
	line []byte
	peek rune
	Out kismetDirective
	Bad bool
}

// The parser calls this method to get each new token.
func (x *queryLex) Lex(yylval *querySymType) int {
	for {
		c := x.next()
		switch c {
		case eof:
			return eof
		case '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '.', '+', '-':
			return x.num(c, yylval)
		case ':', '(', ')':
			return int(c)
		case '<', '>':
			return x.op(c, yylval)
		case '=':
			return EQ

		// Recognize Unicode symbols
		// returning what the parser expects.
		case '≤':
			return LE
		case '≥':
			return GE


		default:
			if 'a' <= c && c <= 'z' || 'A' <= c && c <= 'Z' {
				return x.word(c, yylval)
			}
		}
	}
}

// Lex a number.
func (x *queryLex) num(c rune, yylval *querySymType) int {
	var b bytes.Buffer
	state := 0
	x.add(&b, c)
	if c == '.' {
		state = 1
	}
	L: for {
		c = x.next()
		switch state {
		case 0:
			switch c {
			case '0', '1', '2', '3', '4', '5', '6', '7', '8', '9':
				x.add(&b, c)
			case '.':
				state = 1
				x.add(&b, c)
			case 'e', 'E':
				state = 2
				x.add(&b, c)
			default:
				break L
			}
		case 1:
			switch c {
			case '0', '1', '2', '3', '4', '5', '6', '7', '8', '9':
				x.add(&b, c)
			case 'e', 'E':
				state = 2
				x.add(&b, c)
			default:
				break L
			}
		case 2:
			switch c {
			case '0', '1', '2', '3', '4', '5', '6', '7', '8', '9':
				state = 3
				x.add(&b, c)
			case '-', '+':
				state = 3
				x.add(&b, c)
			default:
				break L
			}
		case 3:
			switch c {
			case '0', '1', '2', '3', '4', '5', '6', '7', '8', '9':
				x.add(&b, c)
			default:
				break L
			}
		}
	}
	x.unpeek(c)
	yylval.num.String = strings.ToLower(b.String())
	yylval.num.Num = &big.Rat{}
	if _, ok := yylval.num.Num.SetString(yylval.num.String); !ok {
		yylval.word = yylval.num.String
		return WORD
	}
	return NUM
}

// Lex a word.
func (x *queryLex) word(c rune, yylval *querySymType) int {
	var b bytes.Buffer
	x.add(&b, c)
	state := 0
	L: for {
		c = x.next()
		switch c {
		case '0', '1', '2', '3', '4', '5', '6', '7', '8', '9':
			x.add(&b, c)
		default:
			if 'a' <= c && c <= 'z' || 'A' <= c && c <= 'Z' {
				x.add(&b, c)
			} else {
				break L
			}
		}
	}
	x.unpeek(c)
	yylval.word = strings.ToLower(b.String())
	return WORD
}

// Lex an operator.
func (x *queryLex) op(c rune, yylval *querySymType) int {
	var b bytes.Buffer
	state := c
	x.add(&b, c)
	c = x.next()
	switch state {
	case '<':
		if c == '=' {
			return LE
		} else {
			x.unpeek(c)
			return LT
		}
	case '>':
		if c == '=' {
			return GE
		} else {
			x.unpeek(c)
			return GT
		}
	default:
		return ERROR
	}
}

// Return the next rune for the lexer.
func (x *queryLex) next() rune {
	if x.peek != eof {
		r := x.peek
		x.peek = eof
		return r
	}
	if len(x.line) == 0 {
		return eof
	}
	c, size := utf8.DecodeRune(x.line)
	x.line = x.line[size:]
	if c == utf8.RuneError && size == 1 {
		log.Print("invalid utf8")
		return x.next()
	}
	return c
}

func (x *queryLex) add(b *bytes.Buffer, c rune) {
	if _, err := b.WriteRune(c); err != nil {
		log.Fatalf("WriteRune: %s", err)
	}
}

func (x *queryLex) unpeek(c rune) {
	if c != eof {
		x.peek = c
	}
}

// The parser calls this method on a parse error.
func (x *queryLex) Error(s string) {
	log.Printf("parse error: %s", s)
	x.Bad = true
}

func parseQuery(line string) elasticDirective {
	q := queryLex{line: []byte(line)}
	queryParse(&q)
	if q.Bad {
		// If parse failed
		if strings.ContainsAny(line,"*?") {
			q.Out.Query = elastic.NewWildcardQuery("_all",line)
		} else {
			q.Out.Query = elastic.NewBoolQuery().Should(
				elastic.NewMatchQuery("_all",line),
				elastic.NewPrefixQuery("_all",line),
			)
		}
	}
	return q.Out
}
