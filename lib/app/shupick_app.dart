import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../presentation/store_shell.dart';
import '../presentation/shared/app_theme.dart';
import 'store_binding.dart';

/// 앱 진입점은 의존성 조립과 공통 테마만 담당합니다.
class ShupickApp extends StatelessWidget {
  const ShupickApp({super.key, this.binding});

  final Bindings? binding;

  @override
  Widget build(BuildContext context) => GetMaterialApp(
    title: 'SHOEPICK',
    debugShowCheckedModeBanner: false,
    initialBinding: binding ?? StoreBinding(),
    theme: ShoepickTheme.light(),
    darkTheme: ShoepickTheme.dark(),
    home: const StoreShell(),
  );
}
