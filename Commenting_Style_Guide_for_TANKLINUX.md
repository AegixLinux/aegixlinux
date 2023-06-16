# Commenting Style Guide for TANKLINUX

The style guide uses a format reminiscent of markdown, with a specified number of hash characters for each section header.

## Regular Comments

`# This is a regular comment`

## Section Headers

We use a standard number of multiple hashes and a pattern reminiscent of markdown for section headers.

### H1 Pattern uses 40 hashes

``` Shell
#########################################
# H1 Heading Title
#########################################
```

### H2 Pattern uses 32 hashes

``` Shell
################################
## H2 Heading Title
################################
```

### H3 Pattern uses 20 hashes

``` Shell
####################
### H3 Heading Title
####################
```

### H4 Pattern also uses 20 hashes

``` Shell
####################
#### H4 Heading Title
####################
```


### H4, H5, H6, Etc Patterns also use 20 hashes

``` Shell
####################
#### H4 Heading Title
####################

####################
##### H5 Heading Title
####################
```

### Function Commenting

#### Description, Input, Operation, Output, Note

If you want to provide a full explanation of a function, please follow this pattern
`#### function_name function:`
`# Description:`
`# Input:`
`# Operation:`
`# Output:`
`# Note:`

#### Example

``` Shell
#### installpkg function:
# Description: Installs a given package using pacman.
# Input: A string representing the package name ($1).
# Operation: The --noconfirm flag automatically answers yes to all prompts.
#            The --needed flag prevents reinstallation of up-to-date packages.
# Output: None directly (affects system state by installing a package).
# Note: All output (stdout and stderr) is redirected to /dev/null to suppress it.
```
