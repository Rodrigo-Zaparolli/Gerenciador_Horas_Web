import 'package:flutter/material.dart';

class BetaControlState {
  const BetaControlState(
      {this.armed = false, this.busy = false, this.status = ''});
  final bool armed, busy;
  final String status;
}

class BetaControls {
  static final requests = ValueNotifier<int>(0);
  static final state =
      ValueNotifier<BetaControlState>(const BetaControlState());
}

class BetaHeaderControl extends StatelessWidget {
  const BetaHeaderControl({super.key});
  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<BetaControlState>(
          valueListenable: BetaControls.state,
          builder: (_, state, child) => IconButton(
              tooltip: state.armed
                  ? 'Desativar escuta da BETA'
                  : 'Ativar escuta da BETA',
              onPressed:
                  state.busy ? null : () => BetaControls.requests.value++,
              icon: Icon(state.armed ? Icons.mic : Icons.mic_none,
                  color: state.armed ? Colors.cyan : null)));
}
