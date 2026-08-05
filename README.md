This .axx file is generated with AI assist.

Default is the FreeBSD version, to change to Linux version, replace the value freebsd of the variable OS in the source with linux

assemble
```
axx x86_64m.axx bf.s -o bf.o
```

link
```
ld bf.o -o bf
```

execute
```
./bf mandelbrot.bf
```
