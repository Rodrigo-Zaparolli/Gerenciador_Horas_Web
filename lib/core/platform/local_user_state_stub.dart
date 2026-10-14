final _values = <String, String>{};
String? read(String key) => _values[key];
bool write(String key, String value) {
  _values[key] = value;
  return true;
}

void remove(String key) => _values.remove(key);
