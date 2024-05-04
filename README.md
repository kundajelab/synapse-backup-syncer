# Description

This script syncs files with Synapse projects  
  
[Example Synapse project](https://www.synapse.org/#!Synapse:syn58961812/files/)  

# Usage
Intended usage: the lab admin runs this file on a schedule, and each user has their own [synapse file manifest](https://python-docs.synapse.org/explanations/manifest_tsv/#example-manifest-file), provided as an env var.
```
# Activate synapseclient environment
bash synapse-syncer.sh example/manifest.tsv
```

# Todo
- [ ] Add dependency handling
- [ ] Add slackbot integration
