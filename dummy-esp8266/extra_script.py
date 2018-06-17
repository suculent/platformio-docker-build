Import("env")

# Consider possible security implications associated with call module.
# from subprocess import call
# from SCons.Script import DefaultEnvironment

print env.Dump()
