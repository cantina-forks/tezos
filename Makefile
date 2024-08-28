all: basic logs full compact dal-basic

NODE_INSTANCE_LABEL ?= instance
STORAGE_MODE ?= default

%.jsonnet:
	jsonnet \
		-J vendors/grafonnet-lib/grafonnet \
		--ext-str node_instance_label="$(NODE_INSTANCE_LABEL)" \
		--ext-str storage_mode="$(STORAGE_MODE)" \
                --ext-str netdata="$(NETDATA)" \
		src/$@ \
			> output/$*.json

clean:
	rm output/*.json

fmt:
	jsonnetfmt -i src/*.jsonnet
	jsonnetfmt -i src/dal/*.jsonnet

basic: octez-basic.jsonnet

logs : octez-with-logs.jsonnet

full: octez-full.jsonnet

compact: octez-compact.jsonnet

dal-basic: dal/dal-basic.jsonnet

octez-compact-new:
	jsonnet \
		-J vendor src/octez-compact-new.jsonnet \
		--ext-str node_instance_label="$(NODE_INSTANCE_LABEL)" \
		> output/$@.json

octez-basic-new:
	jsonnet \
		-J vendor src/octez-basic-new.jsonnet \
		--ext-str node_instance_label="$(NODE_INSTANCE_LABEL)" \
		> output/$@.json

octez-full-new:
	jsonnet \
		-J vendor src/octez-full-new.jsonnet \
		--ext-str node_instance_label="$(NODE_INSTANCE_LABEL)" \
		--ext-str storage_mode="$(STORAGE_MODE)" \
		> output/$@.json

octez-with-logs-new:
	jsonnet \
		-J vendor src/octez-with-logs-new.jsonnet \
		--ext-str node_instance_label="$(NODE_INSTANCE_LABEL)" \
		--ext-str storage_mode="$(STORAGE_MODE)" \
		> output/$@.json

dal-basic-new:
	jsonnet \
		-J vendor src/dal/dal-basic-new.jsonnet \
		--ext-str node_instance_label="$(NODE_INSTANCE_LABEL)" \
		> output/$@.json


new: octez-compact-new octez-basic-new octez-full-new octez-with-logs-new dal-basic-new
