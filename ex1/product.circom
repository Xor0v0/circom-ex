template ProveBigIntegerProduct() {
	signal input in[2];
	signal input recipient;
	signal input ans;
		
    ans === in[0] * in[1];
    signal dummy;
    // dummy <== recipient * recipient;  // right
    dummy <== 2 * recipient; // wrong
}
component main {public [ans, recipient]} = ProveBigIntegerProduct();