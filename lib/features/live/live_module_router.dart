/// Live streaming module router for KazuVera2D
library;

import 'package:flutter_modular/flutter_modular.dart';
import 'live_module.dart';

/// Live streaming module for routing
class LiveModuleRouter extends Module {
  @override
  void routes(r) {
    r.child('/', child: (context) => const LiveModule());
    r.child('/:platformId', child: (context) {
      final platformId = r.args.params['platformId'];
      return LiveModule(initialPlatformId: platformId);
    });
  }
}