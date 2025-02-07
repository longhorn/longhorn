# Longhorn Commandline Interface (longhornctl)

## Summary

Navigating Longhorn's troubleshooting and manual operations documents can be challenging. This proposal introduces the `longhornctl` Longhorn Command-Line Interface (CLI) to enhance user experience. This CLI steamlines operations, making Longhorn's manual operations simpler and more intuitive for users.

### Related Issues

https://github.com/longhorn/longhorn/issues/7927

## Motivation

### Challenges With Current Operations

Currently, Longhorn users often face challenges when performing manual operations such as troubleshooting and non-custom-resource operations. These challenges include:

- The need to refer to extensive documentation for each operations.
- Complex and time-consuming steps for one-time operations.
- Difficulty in gathering information for troubleshooting.
- Manual processes for retrieving data and information during Longhorn failures.

### Goals

This proposal's primary goal is to introduce a Longhorn CLI (`longhornctl`), laying the foundation for simplifying manual Longhorn operations. The specific objective include:

- Providing a single, unified interface for common operations.
- Reducing the time and effort required for one-time operations.
- Streamlining troubleshooting by automating the information collection and error identification.
- Simplifying data retrieval from Longhorn volumes during failures.

#### Initial Implementation

To demonstrate the capabilities of `longhornctl`, the initial Proof of Concept (PoC) will focus on the following operations:

- Preflight installation/uninstallation
- Preflight checking
- Volume trimming
- Replica exporting

Additional operations will be developed on a case-by-case basis to further enhance the `longhornctl` CLI.

### Non-goals [optional]

While this proposal aims to address fundamental manual operations, it does not encompass every existing possible troubleshooting scenario or operation. The focus is on establishing a structured CLI for common use cases.

## Proposal

### User Stories

#### Story 1: Preparation for Longhorn

As a Longhorn user, I want to prepare my environment using the `longhornctl` to easily set up my environment without the need for manual installations or searching through documents.

- Before this enhancement: Users had to refer to documents to either prepare the environment using the Longhorn provided manifest or follow a detailed document to manually set up the environment for each cluster hosts.
- After this enhancement: Users can simplify Longhorn prerequisites setup with a single command.

#### Story 2: One-time operation

As a Longhorn user, I want to perform one-time operations using the `longhornctl` to execute tasks without navigating the Longhorn UI or remembering complex commands.

- Before this enhancement: User need to remember or lookup steps for one-time operations, a process that could be complex and time-consuming.
- After this enhancement: One-time operations are consolidated into a uniflied CLI, removing the need to remember and following complex steps. This improves efficiency and reduce the likelihood of errors.

#### Story 3: Troubleshoot

As a Longhorn user, I want to troubleshoot Longhorn using the `longhornctl` to quickly identify and resolve issues.

- Before this enhancement: Troubleshooting Longhorn requires manual information gathering from various sources, a time-consuming process.
- After this enhancement: The troubleshooting process is streamlined, allowing user to quickly collect information and pinpoint issues. This enhancement improves efficiency and reduces the time needed to resolve Longhorn issues.

#### Story 4: Data-retrival

As a Longhorn user, I want to retrieve data from Longhorn volumes using the `longhornctl` when Longhorn encounters failures.

- Before this enhancement: User had to navigate through complex steps to manually mount Longhorn volumes for data access, a time-consuming and error-prone process.
- After this enhancement: User an easily export data to a specified targeting path using the `longhornctl`, simplifying the process and enhancing the user experience during the Longhorn failures.


### User Experience In Detail

When a user execute the `longhornctl`, they should encounter clear and informative output to enhance their understanding and usage. This includes:
- Detailed command descriptions: Each command is accompanied by a detailed description, providing users with a comprehensive overview of its purpose and usage.
- Help menu at each command layer: User can find help menu at each layer of the command and subcommands that allows user to get detailed information without navigating through external documentation.
- Clear messages and log control: User have the ability to change the log level, allowing them to control the verbolity of output. This ensures that user receive clear logs and results, making it easier to understand the CLI's action and responses.

Examples:
- Showing help at root command:
    ```shell
    > ./bin/longhornctl --help
    Commands for managing Longhorn

    Install And Uninstall Commands:
      install          Install Longhorn extensions
      uninstall        Uninstall Longhorn extensions

    Operation Commands:
      trim             Longhorn trim commands
      export           Export Longhorn

    Troubleshoot Commands:
      check            Check Longhorn
      get              Get Longhorn resources

    Other Commands:
      global-options   Print global options inherited by all scommands

    Use "longhornctl <command> --help" for more information about a given
    command.
    ```
- Showing help at subcommand:
    ```shell
    > ./bin/longhornctl trim --help
    Longhorn trim commands

    Available Commands:
      volume        Trim a Longhorn volume

    Use "longhornctl trim <command> --help" for more information about a given
    command.

    > ./bin/longhornctl trim volume --help
    Trim a Longhorn volume

    Options:
        --longhorn-namespace='longhorn-system':
    	Longhorn namespace

        --name='':
    	Longhorn volume name

    Usage:
      longhornctl trim volume [flags] [options]

    Use "longhornctl trim options" for a list of global command-line options
    (applies to all commands).
    ```
- Clean notification for missing command option flag:
    ```shell
    ERROR[2024-04-23T13:25:30+08:00] Longhorn volume name (--name) is required
    ```
- Clear output of the result:
    ```shell
    INFO[2024-04-23T15:19:16+08:00] Successfully export replica:
     volumes:
      pvc-65789149-430e-41a9-944a-c1f3dc2dc5db:
      - replicas:
        - node: gke-lh-c3y1huang-6lv-lh-c3y1huang-6lv-b30251b0-tq57
          exportedDirectory: /tmp/foo/pvc-65789149-430e-41a9-944a-c1f3dc2dc5db
    INFO[2024-04-23T15:19:16+08:00] Run 'longhornctl export replica stop' to stop exporting the replica
    ```
    ```
    INFO[2024-06-11T14:48:58+08:00] Retrieved preflight checker result:
    ip-10-0-2-5:
      info:
      - Service iscsid is running
      - NFS4 is supported
      - Package nfs-client is installed
      - Package open-iscsi is installed
      - CPU instruction set sse4_2 is supported
      - HugePages is enabled
      - Module nvme_tcp is loaded
      - Module uio_pci_generic is loaded
    ip-10-0-2-71:
      error:
      - Neither iscsid.service nor iscsid.socket is running
      info:
      - NFS4 is supported
      - Package nfs-client is installed
      - Package open-iscsi is installed
      - CPU instruction set sse4_2 is supported
      - HugePages is enabled
      - Module nvme_tcp is loaded
      - Module uio_pci_generic is loaded
    ip-10-0-2-248:
      info:
      - Service iscsid is running
      - NFS4 is supported
      - Package nfs-client is installed
      - Package open-iscsi is installed
      - CPU instruction set sse4_2 is supported
      - HugePages is enabled
      - Module nvme_tcp is loaded
      - Module uio_pci_generic is loaded
    ```

### API changes

Not applicable in this context.

## Design

The `longhornctl` will be based on the existing https://github.com/longhorn/cli, originally designed for Longhorn preflight operations.

### Command

#### Migration to `cobra`

The command library will migrate from `urfave` to `cobra` for managing complex sub-command groupings and more powerful and customizable help menu.

#### Command Groupings

Introduce command groupings to enhance user understandings:
```shell
> ./bin/longhornctl help
Longhorn commandline interface for managing Longhorn

Install And Uninstall Commands:
  install          Install Longhorn extensions
  uninstall        Uninstall Longhorn extensions

Operation Commands:
  trim             Longhorn trim commands
  export           Export Longhorn

Troubleshoot Commands:
  check            Check Longhorn
  get              Get Longhorn resources

Other Commands:
  global-options   Print global options inherited by all scommands

Use "longhornctl <command> --help" for more information about a given
command.
```

#### Command Layer Conventions

Commands will follow a structured format of `verb (primary action)` + `noun (item/entity)` + `specific action`.

```golang
const (
	// The first layer of subcommands (verb)
	SubCmdCheck     = "check"
	SubCmdExport    = "export"
	SubCmdGet       = "get"
	SubCmdInstall   = "install"
	SubCmdTrim      = "trim"
	SubCmdUninstall = "uninstall"

	// The second layer of subcommands (noun)
	SubCmdPreflight = "preflight"
	SubCmdReplica   = "replica"
	SubCmdVolume    = "volume"

	// The third layer of subcommands (specific action to take concerning the action and item of the previous layers)
	SubCmdStop = "stop"
)
```

With these conventions, each command is structured logically:

```
Example usage:
- longhornctl install preflight
- longhornctl get replica
- longhornctl export replica stop
```

#### Example Command Implementation

```golang
func NewCmdGetReplica(globalOpts *types.GlobalCmdOptions) *cobra.Command {
	var replicaGetter = replica.Getter{}

	cmd := &cobra.Command{
		Use:   consts.SubCmdReplica,
		Short: "Get Longhorn replica information",
		Long:  `This command retrieves detailed information about Longhorn replicas.
The information can be used for troubleshooting and understand the state of your replicas.

By default, the command retrieves information about all replicas in the system.
You can optionally filter the results by providing:
- Replica Name: Use the --name flag to specify the replica name you want the details for.
- Volume Name: Use the --volume flag to filter replicas based on the volume they belong to.`,

		PreRun: func(cmd *cobra.Command, args []string) {
			replicaGetter.Image = globalOpts.Image
			replicaGetter.KubeConfigPath = globalOpts.KubeConfigPath
		},

		Run: func(cmd *cobra.Command, args []string) {
			logrus.Infof("Initializing replica getter")
			if err := replicaGetter.Init(); err != nil {
				utils.CheckErr(errors.Wrapf(err, "Failed to initialize replica getter"))
			}

			logrus.Infof("Running replica getter")
			result, err := replicaGetter.Run()
			if err != nil {
				utils.CheckErr(errors.Wrapf(err, "Failed to run replica getter"))
			}

			logrus.Infof("Completed replica getter:\n %v", result)
		},

		PostRun: func(cmd *cobra.Command, args []string) {
			logrus.Debugf("Cleaning up replica getter")
			if err := replicaGetter.Cleanup(); err != nil {
				utils.CheckErr(errors.Wrapf(err, "Failed to cleanup replica getter"))
			}
		},
	}

	utils.SetGlobalOptionsRemote(cmd, globalOpts)

	cmd.Flags().StringVar(&replicaGetter.ReplicaName, consts.CmdOptName, "", "Specify the name of the replica to retrieve information (optional).")
	cmd.Flags().StringVar(&replicaGetter.VolumeName, consts.CmdOptLonghornVolumeName, "", "Specify the name of the volume to retrieve replica information (optional).")
	cmd.Flags().StringVar(&replicaGetter.LonghornDataDirectory, consts.CmdOptLonghornDataDirectory, "/var/lib/longhorn", "Specify the Longhorn data directory. If not provided, the default will be attempted, or it will fall back to the location of longhorn-disk.cfg (optional).")

	return cmd
}
```
- Receiver instance (`replicaGetter`): this is used to handle operation related to the command, such as `Init()`, `Run()`, `Validate()`, `Cleanup()`, etc.
- Short Description (`Short`): provide a brief description of the command, helping user understand its purpose at a glance.
- Long Description (`Long`): a detailed explanation of the command, providing user with comprehensive information about its functionality.
- PreRun Function:
    - Assigns global options to the `replicaGetter` instance
    - Validate the command options assigned to the `replicaGetter` instance.
- Run Function:
    - Invoke receiver `Init()` for initializing `replicaGetter`.
    - Invoke receiver `Run()` to run the actual operation.
    - Check for errors of the invocation, exit with a non-zero code if an error occurs.
- PostRun Function:
    - Invoke receiver `Cleanup()` to clean up resources used by the `replicaGetter` after command execution.
- Global Options (`SetGlobalOptionsRemote`):
    - Sets global options for the subcommand, ensuring consistency and ease of use across all subcommands.
- Command Flags:
    - Defines flag for the command, allowing users to provide additional options and assign it to the `replicaGetter` instance.

#### Remote (longhornctl)

The `longhornctl` command is responsible for managing the required resources within the Kubernetes cluster for in-cluster operations, such as ConfigMap, DaemonSet, etc.
- Resource Management: This command handles the creation and deletion of the resources like ConfigMap and DaemonSet within the Kubernetes cluster. For instance, the DaemonSet that is responsible for running operations related to the command actions.
- Monitoring: The `longhornctl` command monitors the status of the DaemonSet containers. This proactive monitoring block ensures that actions are completed and allows for error handling.
- Error Handling and Log Retrieval: In case of an action failure, the command retrieves the logs of the specific container involved. These logs shall provide users with clear understandings of the failure.
- Results Output: For actions that yields a collection of information, the command formats the presents the result in a user-friendly YAML formal. These ensures that users can easily interpret the output.

#### Local (longhornctl-local)

The `longhornctl-local` command is designed to run within a DaemonSet pod inside the Kubernetes cluster, focusing on managing interactions within the cluster environment, including both in-cluster and host operations.
- Host interactions: When executed within the Daemonset pod, the `longhornctl-local` command can interact with the host system. This could involve tasks such as:
    - Managing storage devices.
    - Interacting with the host filesystem.
    - Executing system-level commands.

### Code Structure

- cmd: Contains the main command files for both local and remote binaries. Keep the directories separate for clarity.
  - /local
    - /subcmd
    - longhornctl-local.go
  - /remote
    - /subcmd
    - longhornctl.go
- /dapper: Houses the build script for creating local and remote binaries.
  - build:
    ```bash
    # Binary runs local to the Kubernetes cluster
    build_app local longhornctl-local

    # Binary runs remote to the Kubernetes cluster
    build_app remote longhornctl
    ```
- /pkg
  - /consts: Centralized constants.
  - /local: Package for local operations to the Kubernetes cluster.
  - /remote: Package for remote operations to the Kubernetes cluster.
  - /types: Centralized types definitions to ensure consistency.
  - /utils: Contains utilities categorized by purpose, specific for this repository (For common utilities, use `go-common-lib`).

Example:
```
cli
|
+-- cmd
| +-- local .......................... Command for operations within Kubernetes cluster.
| | +-- subcmd ....................... Subcommands specific to local operations.
| | | +-- check.go
| | | +-- get.go
| | | +-- install.go
| | | +-- trim.go
| | +-- README.md
| | +-- longhornctl-local.go ......... Main command file for local operations.
| +-- remote ......................... Commands for operations outside the Kubernetes cluster.
|   +-- subcmd ....................... Subcommands specific to remote operations.
|   | +-- check.go
|   | +-- get.go
|   | +-- install.go
|   | +-- trim.go
|   +-- longhornctl.go ............... Main command file for remote operations.
+-- dapper
| +-- build .......................... Build file to create local/remote binaries.
+-- pkg
  +-- consts ......................... Constants used throughout the project.
  | +-- cmd.go
  | +-- env.go
  | +-- longhorn.go
  | +-- prflight.go
  | +-- replica.go
  | +-- spdk.go
  | +-- longhornctl.go
  | +-- volume.go
  +-- local .......................... Package for local command operations.
  | +-- preflight
  | | +-- checker.go ................. Logic for checking pre-flight conditions.
  | | +-- installer.go ............... Logic for installing packages.
  | | +-- pkgmgr ..................... Package managers for various systems.
  | |   +-- apt.go
  | |   +-- pacman.go
  | +-- replica
  | | +-- getter.go .................. Logic for getting replica information.
  | | +-- exporter.go ................ Logic for exporting replica.
  | +-- volume
  | | +-- trimmer.go ................. Logic for trimming volume.
  +-- remote ......................... Package for remote command operations.
  | +-- preflight
  | | +-- checker.go ................. Logic for Kubernetes resource handling.
  | +-- replica
  | | +-- getter.go .................. Logic for Kubernetes resource handling.
  | +-- volume
  |   +-- trimmer.go ................. Logic for Kubernetes resource handling.
  +-- types
  | +-- cmd.go ....................... Definitions for command-related types.
  | +-- pod.go ....................... Definitions for Kubernetes Pod related types.
  | +-- replica.go ................... Definitions for Longhorn Replica related types.
  | +-- volume.go .................... Definitions for Longhorn Volume related types.
  +-- utils
    +-- kubernetes
    | +-- runtime.go ................. Utility functions related to Kubernetes runtime.
    +-- longhorn
    | +-- longhorn.go ................ Utility functions related to Longhorn.
    +-- cmd.go ....................... Utility functions related to commands.
    +-- utils.go ..................... Utility general functions.
```

### Feature

#### Install Preflight

##### Remote Command (`longhornctl install preflight`)

- Introduce command to prepare and create a `longhorn-preflight-installer` DaemonSet.
- Include `--operating-system` command option to accommodate operating systems that do not include a package manager, such as container-optimized OS (COS).
- When no operating system is specified, create a DaemonSet include:
    - An init-container executing `longhornctl-local install preflight`.
    - A container running a pause image as an indicator to signal the completion of the `longhornctl-local` command in the init-container.
- When operating system is specified to `cos`, create:
    - a ConfigMap include:
        - The entrypoint.sh script.
    - a DaemonSet include:
        - Container running the `entrypoint.sh` script. Ref: [longhorn-gke-cos-node-agent.yaml
        ](https://github.com/longhorn/longhorn/blob/2cbedf3902e72e347eed1eb8a45768462a4dd76b/deploy/prerequisite/longhorn-gke-cos-node-agent.yaml)
        - Readiness probe for successful installation indication.
        - Liveness probe for error detection.

##### Local Command (`longhornctl-local install preflight`)

- Transition commandline library from `urfave` to `cobra`.
- Refactor command returns for error handling.
- Retain the existing functionality for installation via package manager.

#### Check Preflight

##### Remote (`longhornctl check preflight`)

- Introduce command to prepare and create a `longhorn-preflight-checker` DaemonSet.
- The DaemonSet include:
    - An init-container executing `longhornctl-local check preflight`.
    - A container running a pause image as an indicator to signal the completion of the `longhornctl-local` command in the init-container.
- Post-command cleanup:
    - Upon command completion, cleanup the DaemonSet.

##### Local (`longhornctl-local check preflight`)

- Transition commandline library from `urfave` to `cobra`.
- Refactor command returns for error handling.
- Retain the existing functionality for checking via package manager and services.

#### Trim Volume

##### Remote (`longhornctl trim volume`)

- Introduce command to prepare and create a `longhorn-volume-trimmer` DaemonSet.
- The DaemonSet include:
    - An init-container executing `longhornctl-local trim volume`.
    - A container running a pause image as an indicator to signal the completion of the `longhornctl-local` command in the init-container.
- Post-command cleanup:
    - Upon command completion, cleanup the DaemonSet.

##### Local (`longhornctl-local trim volume`)

- Implement logic to detect and execute `fstrim` for `RWO` and `RWX` volumes.

#### Get Replica

##### Remote (`longhornctl get replica`)

- Introduce command to prepare and create a `longhorn-replica-getter` DaemonSet.
- The DaemonSet include:
    - A shared volume mount for the result output to `replica.json`.
    - An init-container executing `longhornctl-local get replica`.
    - A container running `cat "replica.json"`.
- When the DaemonSet is running successfully, retrieve the log of the container outputting the `replica.json`, then unmarshal JSON to YAML and output to the users.
- Post-command cleanup:
    - Upon command completion, cleanup the DaemonSet.

##### Local (`longhornctl-local get replica`)

- Implement logic to collect replica information from host directories and `volume.meta` files:
    ```golang
    type ReplicaCollection struct {
    	Replicas map[string][]*ReplicaInfo `json:"replicas" yaml:"replicas"`
    }

    // ReplicaInfo holds information about a replica.
    type ReplicaInfo struct {
    	Node              string                `json:"node,omitempty" yaml:"node,omitempty"`
    	Directory         string                `json:"directory,omitempty" yaml:"directory,omitempty"`
    	IsInUse           *bool                 `json:"isInUse,omitempty" yaml:"isInUse,omitempty"`
    	VolumeName        string                `json:"volumeName,omitempty" yaml:"volumeName,omitempty"`
    	Metadata          *lhmgrutil.VolumeMeta `json:"metadata,omitempty" yaml:"metadata,omitempty"`
    	Error             string                `json:"error,omitempty" yaml:"error,omitempty"`
    	ExportedDirectory string                `json:"exportedDirectory,omitempty" yaml:"exportedDirectory,omitempty"`
    }
    ```
- Output the collected information to `replica.json` within the shared volume mount.

#### Export Replica

##### Remote (`longhornctl export replica`)

- Introduce command to prepare and create:
    - A `longhorn-replica-exporter` ConfigMap
    - A `longhorn-replica-exporter` DaemonSet
- The ConfigMap includes and `entrypoint.sh` responsible for:
    - Read the replica information from the `replica.json` in the shared volume mount.
    - Pausing the daemonset pod if the replica is not on the pod node.
    - Checking if the replica is in use.
    - Running `launch-simple-longhorn ${VOLUME_NAME} ${VOLUME_SIZE} &`
    - Creating pre-stop script.
    - Mouting the device to the target host path.
- The DaemonSet includes:
    - A shared volume mount for the result output to `replica.json`.
    - An init-container executing `longhornctl-local get replica` for collecting the replica information and output to the `replica.json` in the shared volume mount.
    - A container running `entrypoint.sh` in the engine image.
    - A readiness probe to check for action completion.
    - A pre-stop hook to execute pre-stop script for the host mount point cleanup.

##### Local (`None`)

No local command for replica exporting, as the dependent `launch-simple-longhorn` is built in the engine image.

### Test plan

1. Command execution testings:
    - Install and uninstall commands
    - Operating commands
    - Troubleshooting commands
    - Global options printing
1. Command help testings:
    - Run `longhornctl --help` and verify that all sub-commands are displayed
    - Run `longhornctl <subcommand> --help` for each sub-command and verify detailed help information is provided.
1. Error Handling Testing:
    - Execute commands with incorrect or missing options, and verify error message are displayed to guide users on correct usage.
1. Functionality Testing:
    - Test each command with valid input to ensure they perform the intended operations.
    - Verify correct behavior and output for each command.
1. Cross-platform testing:
    - Test `longhornctl` on different operating systems to ensure compatibility.

### Upgrade strategy

No specific upgrade strategy is needed currently for this phase of the project.

## Note [optional]

`None`
