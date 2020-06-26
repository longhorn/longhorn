echo "Update imagePullPolicy to be Always for manager, UI, driver deployer, engine image"

# Update imagePullPolicy for Longhorn manager daemonset
kubectl patch daemonset longhorn-manager -n longhorn-system -p \
'{"spec":{"template":{"spec":{"containers":[{"name":"longhorn-manager", "imagePullPolicy":"Always"}]}}}}'
sleep 5

# Update imagePullPolicy for Longhorn UI deployment
kubectl patch deployment longhorn-ui -n longhorn-system -p \
'{"spec":{"template":{"spec":{"containers":[{"name":"longhorn-ui", "imagePullPolicy":"Always"}]}}}}'
sleep 5

# Update imagePullPolicy for Longhorn Driver Deployer deployment
kubectl patch deployment longhorn-driver-deployer -n longhorn-system -p \
'{"spec":{"template":{"spec":{"containers":[{"name":"longhorn-driver-deployer", "imagePullPolicy":"Always"}]}}}}'
sleep 1
echo "wait 15s to make sure that the updated longhorn manager pods come up ..."
sleep 15

# Update all imagePullPolicy for Longhorn Engine Image Daemonsets
temp_file='./.engine-image-daemon-list'
kubectl get daemonsets -n longhorn-system | grep -oE "engine-image-ei-.{8}" > ${temp_file}

while IFS= read -r line
do
        kubectl patch daemonset ${line} -n longhorn-system -p \
                "{\"spec\":{\"template\":{\"spec\":{\"containers\":[{\"name\":\"${line}\", \"imagePullPolicy\":\"Always\"}]}}}}"
        sleep 5
done < ${temp_file}

rm ${temp_file}

echo "Warning: Make sure check and wait for all pods running again!"
echo "Current status: (Ctl+c to exit)"
kubectl get pods -w -n longhorn-system
