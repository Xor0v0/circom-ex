# Circom拾遗

## 1. Recap signal vs var

### signal

由circom语言构建的算术电路的操作对象是 signal ，每一个 signal 代表着一个有限域元素，signal 关键字不仅可以初始化一个 signal ，还可以初始化一个 signal 数组。

signal类型可以分为三类，分别是 `input` , `output`, `intermediate` 。前两者需要分别使用关键字 `input` 和 `output` 。Signal 类型只能被赋值一次，即 immutable。

Visibility：所有的input signal默认都是private的，所有的 output 和 public input 都是 public 的，intermediate signal永远是private的.

另一个非常重要的点在于：所有的 signal 在编译期间都被视为 **unknown** ，即使给它赋予了一个常量也不会视为 Known。这样做的原因是这样做的原因是提供一个精确的可判定定义，即哪些构造是允许的，哪些不允许，而不取决于编译器检测 signal是否总是恒定值的能力。

### var

Var 类型有助于计算不需要立即被约束的信息，即它在编译时是已知known的。

这是非常有用的，一方面它可以承担一些 signal 无法进行的计算（整除、移位、除法等），另一方面它可以产生已知条件用于负责分支语句，可以多次赋值用于循环语句。

Var本质上就只有两种情况，一种是常量，另一种是与signal相关的表达式。前者很好理解，对于后者，你可以想象成一个wrapper，当var参与约束时，它会被展开成关于signal的表达式。signal则不同，如果对intermediate signal【只可能是它】计算关于signal的表达式，则它会计算出相应的域元素，再参与约束。IsZero template是一个极佳的学习范例：

```circom
template IsZero() {
		signal input in;
  	signal output out;

  	signal inv;

  	inv <-- in!=0 ? 1/in : 0;

  	out <== -in*inv +1;
 		in*out === 0;
}
```

`inv` 的赋值涉及到除法，这不满足二次约束，因此我们需要在算术电路之外计算值，使其成为 0 或者 倒数，然后把 inv 作为约束的一部分来强制它为正确值。这就是所谓“计算，然后约束”模式。

当把上述代码替换成：

```circom
template IsZero() {
		signal input in;
  	signal output out;

  	var inv;

  	inv = in!=0 ? 1/in : 0;

  	out <== -in*inv +1;
  	in*out === 0;
}
```

这个代码将会报错：非二次约束。这正是因为 var 仅仅是一个包装，它在参与约束时会展开成关于signal的计算表达式。更直接一点，在约束out时，上述代码最终会被解释为非平凡的计算，进而使得整个约束不满足二次关系。

## 2. Constraint generation

下面开始进入正题：探究Circom约束生成的一些误区。

时刻记住：Circom的编译器只接受关于singal的二次约束。这意味着

```circom
template Example {
		signal input a;
    signal input b;
    signal output aa;
    signal output bb;
    signal output ab;
    
    aa <== 2 * a; // 不会生成约束
    bb <== b * b; // 会生成约束
    ab <== 2 * a * b; // 会生成约束
}
```

### 关于For循环

在 for 循环语句中，经常需要使用 var 去重复接受赋值。观察下面的template：

```
template Example () {
    signal input a[5];
    signal output sum;
    
    var acc;
    for (var i = 0; i < 5; i++) {
        acc += a[i];
    }
    sum <== acc;
}

component main = Example();

/* INPUT = {
    "a": ["1", "2", "3", "4", "5"]
} */
```

这个 template 中 acc 是五个 signal 的线性表达式： `acc = a[0] + a[1] + a[2] + a[3] + a[4] ` .因此对于 sum 的约束可以看作 ： `sum <== a[0] + a[1] + a[2] + a[3] + a[4] ` .但是根据 circom 语言的规则，这个约束不是二次约束，因此不会产生任何约束。其编译出来的 r1cs 信息为：

```
template instances: 1
non-linear constraints: 0
linear constraints: 0
public inputs: 0
public outputs: 0
private inputs: 6
private outputs: 0
wires: 1
labels: 7
```

那么这个模版如何约束最终输出的结果是这个输入数组的元素之和呢？【TODO】

### 关于未使用的signal的处理

在circom开发中，对于未使用到的signal往往也要做约束处理，参考0xPARC的[漏洞归类](https://github.com/0xPARC/zk-bug-tracker#:~:text=5.-,Unused Public Inputs Optimized Out,-Many circuits will)。

这里我做了一个简单小实验，我把未使用的signal的约束从二次约束（即平方）修改为线性约束。这样的话circom编译器就不会对其进行生成约束。正如0xPARC文章所述，我可以由此生成任意的证明。

```circom
template ProveBigIntegerProduct {
		signal input in[2];
		signal input recipient;
		signal input ans;
		
		ans === in[0] * in[1];
		signal dummy;
		// dummy <== recipient * recipient;  // right
		dummy <== 2 * recipient; // wrong
}
component main {public [ans, recipient]} = ProveBigIntegerProduct();
```

假设业务逻辑为：证明者需要证明它知道两个大素数的乘积为ans，并且指定recipient为Vitalik的地址（0xab5801a7d398351b8be11c439e05c5b3259aec9b）以获得奖励。

假设ans=145774017109696730010400470846820337467, 两个素数分别为a=13647322257729719467, b=10681510581838254001. 这个电路模版是欠约束的，recipient没有被正确约束到，因此可以为此电路生成任意个proof。

实验流程：采用Groth16证明系统，首先

### 总结

上述两种情况，我认为其实是同一个问题：如何正确约束线性signal关系？

### 补充

>  Po: 第二个确实是个坑，out <== 5* in那个例子，确实不会生成constraint。这是circom的一个坑，必须使用quadratic形式
>
> Xor0v0: 第一个案例中var类型也能用 ===？
>
> Po: 嗯，var可以用来生成trace。不然很复杂的电路比如hash，就很难做。

> Keep: 第一个例子的结果也不符合我的理解，应该是有1个约束(b === sum)。使用gnark验证是可以生成一个约束的。
