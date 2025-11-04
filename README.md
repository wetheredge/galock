# (G)itHub (A)ctions (Lock)file

This is a minimal tool to manage a lockfile for GitHub actions. It checks that
all workflows and custom composite actions use only actions in the lockfile, and
only the locked revision.

```shell
$ galock help
usage:
  galock [options] help                # print this usage
  galock [options] list [--json]       # list all actions in the lockfile and their tags
  galock [options] check               # check that all workflows match the lockfile
  galock [options] set <action> <tag>  # set the tag used for an action and update workflows
  galock [options] rm <action> <tag>   # remove an action from the lockfile

options:
  --cwd <path>  # set the working directory```
