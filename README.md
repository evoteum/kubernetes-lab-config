[//]: # (STANDARD README)
[//]: # (https://github.com/RichardLitt/standard-readme)
[//]: # (----------------------------------------------)
[//]: # (Uncomment optional sections as required)
[//]: # (----------------------------------------------)

[//]: # (Title)
[//]: # (Match repository name)
[//]: # (REQUIRED)

# kubernetes-lab-config

[//]: # (Banner)
[//]: # (OPTIONAL)
[//]: # (Must not have its own title)
[//]: # (Must link to local image in current repository)


[//]: # (Badges)
[//]: # (OPTIONAL)
[//]: # (Must not have its own title)


[//]: # (Short description)
[//]: # (REQUIRED)
[//]: # (An overview of the intentions of this repo)
[//]: # (Must not have its own title)
[//]: # (Must be less than 120 characters)
[//]: # (Must match GitHub's description)

Cluster Configuration

[//]: # (Long Description)
[//]: # (OPTIONAL)
[//]: # (Must not have its own title)
[//]: # (A detailed description of the repo)

Provides configuration manifests to allow services to run in the cluster.

## Table of Contents

[//]: # (REQUIRED)
[//]: # (Delete as appropriate)

[//]: # (TOCGEN_TABLE_OF_CONTENTS_START)

- [Background](#background)
- [Install](#install)
- [Usage](#usage)
- [Documentation](#documentation)
- [Repository Configuration](#repository-configuration)
- [Contributing](#contributing)
- [License](#license)
    - [Code](#code)
    - [Non-code content](#non-code-content)

[//]: # (TOCGEN_TABLE_OF_CONTENTS_END)

[//]: # (## Security)
[//]: # (OPTIONAL)
[//]: # (May go here if it is important to highlight security concerns.)


## Background
[//]: # (OPTIONAL)
[//]: # (Explain the motivation and abstract dependencies for this repo)

This provides all the tooling necessary to make the cluster usable, such as,
- Rook
- Crossplane
- MetalLB

Installation of off-the-shelf tools is done via the kubernetes-lab-services repository.


## Install

[//]: # (Explain how to install the thing.)
[//]: # (OPTIONAL IF documentation repo)
[//]: # (ELSE REQUIRED)

Almost nothing to install (GitOps FTW!) with one exception.

### OpenBao initialisation

OpenBao must be initialised manually once after first deployment. This is an
unavoidable bootstrap step: the initialisation process generates unseal keys and
a root token that cannot be committed to git or managed declaratively without a
pre-existing secret store.

Run [`scripts/init-openbao.sh`](scripts/init-openbao.sh), which calls
`bao operator init` against `openbao-0` and walks you through unsealing all 3
pods. **Save every line of the init output (5 unseal keys + root token)
somewhere secure and offline before continuing** — losing them after this point
makes everything in OpenBao permanently unrecoverable.

```bash
./scripts/init-openbao.sh
```

OpenBao uses Shamir secret sharing with no auto-unseal configured, so unseal
state lives in each pod's memory independently — there's no single API call
that unseals the whole cluster. This means **the unseal step has to be
repeated by hand after every pod restart** (upgrades, reschedules, crashes),
not just the first time. The script's unseal loop can be re-run on its own for
that — answer "n" when it asks about running init again. The standard fix for
this friction is auto-unseal via a cloud KMS, but that has its own bootstrap
problem here (you'd need AWS credentials to create the KMS key, but need
OpenBao initialised to store AWS credentials) — worth revisiting once the
cluster is past initial bootstrap.

Everything after initialisation — auth methods, policies, secrets engines, and
secrets — is managed via GitOps.

## Usage
[//]: # (REQUIRED)
[//]: # (Explain what the thing does. Use screenshots and/or videos.)

Ansible configures ArgoCD to look at the [root](root) directory, where you will find the root applications. These point
to their applicable directories, except the helm application which points at our kubernetes-lab-services repository.

[//]: # (Extra sections)
[//]: # (OPTIONAL)
[//]: # (This should not be called "Extra Sections".)
[//]: # (This is a space for ≥0 sections to be included,)
[//]: # (each of which must have their own titles.)



## Documentation

Further documentation is in the [`docs`](docs/) directory, including
[disaster recovery backup setup](docs/backup.md) (manual AWS/OpenBao bootstrap steps).

## Repository Configuration

> [!WARNING]  
> This repo is controlled by OpenTofu in the [estate-repos](https://github.com/evoteum/estate-repos) repository.  
>  
> Manual configuration changes will be overwritten the next time OpenTofu runs.


[//]: # (## API)
[//]: # (OPTIONAL)
[//]: # (Describe exported functions and objects)



[//]: # (## Maintainers)
[//]: # (OPTIONAL)
[//]: # (List maintainers for this repository)
[//]: # (along with one way of contacting them - GitHub link or email.)



[//]: # (## Thanks)
[//]: # (OPTIONAL)
[//]: # (State anyone or anything that significantly)
[//]: # (helped with the development of this project)



## Contributing
[//]: # (REQUIRED)
If you need any help, please log an issue and one of our team will get back to you.

PRs are welcome.


## License
[//]: # (REQUIRED)

### Code

All source code in this repository is licenced under the [GNU Affero General Public License v3.0 (AGPL-3.0)](https://www.gnu.org/licenses/agpl-3.0.en.html). A copy of this is provided in the [LICENSE](LICENSE).

### Non-code content

All non-code content in this repository, including but not limited to images, diagrams or prose documentation, is licenced under the [Creative Commons Attribution-ShareAlike 4.0 International](https://creativecommons.org/licenses/by-sa/4.0/) licence.
