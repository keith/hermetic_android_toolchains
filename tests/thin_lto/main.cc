extern "C" int thin_lto_value(void);

int main() { return thin_lto_value() == 42 ? 0 : 1; }
