import sys
import asyncio
import logging
from pathlib import Path
from kubernetes import client, config, watch

NAMESPACE = "default"
NODE_PREFIX = "jmoody-work"
NODE_COUNT = 100
TEMPLATE_FILE = "statefulset.yaml"
KUBE_CONFIG = None
KUBE_CONTEXT = None
# KUBE_CONFIG = "kubeconfig"
# KUBE_CONTEXT = "jmoody-test-jmoody-control2"


def create_sts_deployment(count):
    # @NODE_NAME@ - schedule each sts on a dedicated node
    # @STS_NAME@ - also used for the volume-name
    # create 100 stateful-sets
    for i in range(count):
        create_sts_yaml(i + 1)


def create_sts_yaml(index):
    content = Path(TEMPLATE_FILE).read_text()
    content = content.replace("@NODE_NAME@", NODE_PREFIX + str(index))
    content = content.replace("@STS_NAME@",  "sts" + str(index))
    file = Path("out/sts" + str(index) + ".yaml")
    file.parent.mkdir(parents=True, exist_ok=True)
    file.write_text(content)


async def watch_pods_async():
    log = logging.getLogger('pod_events')
    log.setLevel(logging.INFO)
    v1 = client.CoreV1Api()
    w = watch.Watch()
    for event in w.stream(v1.list_namespaced_pod, namespace=NAMESPACE):
        process_pod_event(log, event)
        await asyncio.sleep(0)


def process_pod_event(log, event):
    log.info("Event: %s %s %s" % (event['type'], event['object'].kind, event['object'].metadata.name))
    if 'ADDED' in event['type']:
        pass
    elif 'DELETED' in event['type']:
        pass
    else:
        pass


async def watch_pvc_async():
    log = logging.getLogger('pvc_events')
    log.setLevel(logging.INFO)
    v1 = client.CoreV1Api()
    w = watch.Watch()
    for event in w.stream(v1.list_namespaced_persistent_volume_claim, namespace=NAMESPACE):
        process_pvc_event(log, event)
        await asyncio.sleep(0)


def process_pvc_event(log, event):
    log.info("Event: %s %s %s" % (event['type'], event['object'].kind, event['object'].metadata.name))
    if 'ADDED' in event['type']:
        pass
    elif 'DELETED' in event['type']:
        pass
    else:
        pass


async def watch_va_async():
    log = logging.getLogger('va_events')
    log.setLevel(logging.INFO)
    storage = client.StorageV1Api()
    w = watch.Watch()
    for event in w.stream(storage.list_volume_attachment):
        process_va_event(log, event)
        await asyncio.sleep(0)


def process_va_event(log, event):
    log.info("Event: %s %s %s" % (event['type'], event['object'].kind, event['object'].metadata.name))
    if 'ADDED' in event['type']:
        pass
    elif 'DELETED' in event['type']:
        pass
    else:
        pass


if __name__ == '__main__':
    # create the sts deployment files
    create_sts_deployment(NODE_COUNT)

    # setup the monitor
    log_format = '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    logging.basicConfig(stream=sys.stdout,
                        level=logging.INFO,
                        format=log_format)
    config.load_kube_config(config_file=KUBE_CONFIG,
                            context=KUBE_CONTEXT)
    logging.info("scale-test started")

    # datastructures to keep track of the timings
    # TODO: process events and keep track of the results
    #       results should be per pod/volume
    #       information to keep track: pod index per sts
    #       volume-creation time per pod
    #       volume-attach time per pod
    #       volume-detach time per pod
    pvc_to_va_map = dict()
    pvc_to_pod_map = dict()
    results = dict()

    # start async event_loop
    event_loop = asyncio.get_event_loop()
    event_loop.create_task(watch_pods_async())
    event_loop.create_task(watch_pvc_async())
    event_loop.create_task(watch_va_async())
    event_loop.run_forever()
    logging.info("scale-test-finished")
