.PHONY: default deploy clean redeploy

default: deploy

ct.yml:
	./ignite.py > ct.yml

ignition.json: ct.yml
	cat ct.yml | docker run -i dharmab/ct:0.4.1 > ignition.json

deploy: ignition.json
	vagrant up

clean:
	vagrant destroy -f
	$(RM) ct.yml ignition.json ignition.json.merged

redeploy: clean deploy
