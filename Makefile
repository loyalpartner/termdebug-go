.PHONY: test
test:
	sh scripts/test.sh
# dlv debug --log --log-output rpc --log-dest .log.txt ./main.go
#tail -f .log.txt|grep "{.*}" | sed "s/[^{}]*\({.*}\)[^{}]*/\1/p"  | jq
