import 'package:flutter/material.dart';

class UserCache {
  static final UserCache _instance = UserCache._internal();
  factory UserCache() => _instance;
  UserCache._internal();

  ImageProvider? fotoPerfilProvider;
  String userName = '';
  bool carregado = false;

  void limparCache() {
    fotoPerfilProvider = null;
    userName = '';
    carregado = false;
  }
}
