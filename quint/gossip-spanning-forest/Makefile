TRACES_DIR := traces

test:
	mkdir -p ${TRACES_DIR}/tests
	quint test --verbosity=3 --main spanningForestTest --match t1 --max-samples 10 spanningForestTest.qnt
	quint test --verbosity=3 --main spanningForestTest --match t2 --max-samples 10 spanningForestTest.qnt
.PHONY: test

traces:
	time ./gen-traces.sh ${PROP}
.PHONY: traces
