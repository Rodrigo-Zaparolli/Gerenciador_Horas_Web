import 'package:web/web.dart' as web;
import '../config/pilot_feature_access.dart';
bool redirectPilotAccount({required String? uid,required String? email}){
  if(uid==null)return false;
  final allowed=email?.trim().toLowerCase()==PilotFeatureAccess.ownerEmail;
  const pilot=bool.fromEnvironment('PERSONAL_PILOT');
  if(allowed==pilot)return false;
  web.window.location.replace(allowed?'/piloto/':'/');
  return true;
}
