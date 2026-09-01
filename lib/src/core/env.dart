import 'package:envied/envied.dart';

part 'env.g.dart';

@Envied(path: '.env')
abstract class Env {
  @EnviedField(varName: 'BASE_URL')
  static const String baseUrl = _Env.baseUrl;
  
  // @EnviedField(varName: 'BANK_ID')
  // static const String bankId = _Env.bankId;
}
