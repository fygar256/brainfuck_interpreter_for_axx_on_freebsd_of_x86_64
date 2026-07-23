This .axx file is generated with AI assist.

assemble
```
axx x86_64.axx bf.s -o bf.o

or

axx x86_64.axx bf_with_macro.s -o bf.o
```

link
```
ld bf.o -o bf
```

execute
```
./bf mandelbrot.bf
```
