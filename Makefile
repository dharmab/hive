.PHONY: default deploy clean redeploy

default: deploy

ignition.json:
	./ignite.py > ignition.json 

deploy: ignition.json
	vagrant up

clean:
	vagrant destroy -f
	$(RM) ignition.json ignition.json.merged

redeploy: clean deploy
