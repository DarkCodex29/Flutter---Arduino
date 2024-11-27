import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:app_preguntas/controller.dart';
import 'package:permission_handler/permission_handler.dart';

class QuizPage extends StatefulWidget {
  const QuizPage({super.key});

  @override
  QuizPageState createState() => QuizPageState();
}

class QuizPageState extends State<QuizPage> {
  final QuizController controller = Get.put(QuizController());
  String headerText = "BLITO PREGUNTA";

  // Colores principales
  final Color teamAColor = const Color(0xFFFA9401);
  final Color teamBColor = const Color(0xFF346B80);
  final Color neutralColor = const Color(0xFFFFD85F);
  final Color progressBarColor = const Color(0xFF00E676);

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      await requestPermissions(); // Solicita permisos
      await controller.loadQuestions(); // Carga las preguntas
    } catch (e) {
      log("Error en la inicialización de la app: $e");
      Get.snackbar("Error", "No se pudo inicializar la aplicación.");
    }
  }

  Future<void> requestPermissions() async {
    try {
      if (await Permission.bluetooth.isGranted &&
          await Permission.bluetoothScan.isGranted &&
          await Permission.bluetoothConnect.isGranted &&
          await Permission.locationWhenInUse.isGranted) {
        log("Todos los permisos ya están concedidos.");
        return; // Salir si los permisos ya están concedidos
      }

      final status = await [
        Permission.bluetooth,
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ].request();

      if (status[Permission.bluetooth]!.isDenied ||
          status[Permission.bluetoothScan]!.isDenied ||
          status[Permission.bluetoothConnect]!.isDenied) {
        Get.snackbar(
          "Permiso requerido",
          "La aplicación necesita acceso a Bluetooth para funcionar correctamente.",
        );
      }

      if (status[Permission.locationWhenInUse]!.isDenied) {
        Get.snackbar(
          "Permiso requerido",
          "Se necesita acceso a la ubicación para detectar dispositivos Bluetooth.",
        );
      }
    } catch (e) {
      log("Error al solicitar permisos: $e");
      Get.snackbar("Error", "Ocurrió un error al solicitar permisos.");
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void updateTime() {
    setState(() {});
  }

  void onTimeUp() {
    controller.nextQuestion(onGameFinished: showResult);
  }

  void togglePause() {
    if (!controller.isConnected.value) {
      showWarning(
          "Debe conectarse a un dispositivo Bluetooth para iniciar el juego.");
      return;
    }
    controller.togglePause();
    setState(() {
      headerText = controller.isPaused.value
          ? "BLITO PREGUNTA"
          : "Equipo ${controller.currentTeam.value}";
    });
    if (!controller.isPaused.value) {
      controller.startTimer(updateTime, onTimeUp);
    }
  }

  void resetGame() {
    controller.resetGame();
    setState(() {
      headerText = "BLITO PREGUNTA";
    });
  }

  void checkAnswer(String answer) {
    if (!controller.isConnected.value) {
      showWarning("Debe conectarse a un dispositivo Bluetooth.");
      return;
    }

    controller.checkAnswer(answer, () {
      showWaitingForArduino();
      controller.nextQuestion(onGameFinished: showResult);
    });
  }

  void showResult() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Resultados"),
          content: Obx(() => Text(
              "Puntuación Equipo A: ${controller.scoreA.value}\nPuntuación Equipo B: ${controller.scoreB.value}")),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                resetGame();
              },
              child: Text(
                "Jugar de nuevo",
                style: TextStyle(color: neutralColor),
              ),
            ),
          ],
        );
      },
    );
  }

  void showWarning(String message) {
    Get.defaultDialog(
      title: "Advertencia",
      middleText: message,
      textConfirm: "Aceptar",
      onConfirm: () => Get.back(),
    );
  }

  void showWaitingForArduino() {
    Get.defaultDialog(
      barrierDismissible: false,
      title: "Esperando respuesta",
      middleText: "Esperando respuesta del Arduino...",
    );
  }

  Future<void> showBluetoothDevices() async {
    controller.startDiscovery();
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return Obx(() {
          if (controller.isScanning.value) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView.builder(
            itemCount: controller.discoveredDevices.length,
            itemBuilder: (context, index) {
              final device = controller.discoveredDevices[index].device;
              return ListTile(
                title: Text(device.name ?? "Dispositivo sin nombre"),
                subtitle: Text(device.address),
                onTap: () {
                  controller.connectToHC05(device.address);
                  Navigator.pop(context);
                },
              );
            },
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (!controller.isQuestionsLoaded.value) {
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      }

      final question =
          controller.questions[controller.currentQuestionIndex.value];
      final optionLabels = ['a', 'b', 'c', 'd'];
      Color activeColor = controller.isPaused.value
          ? neutralColor
          : (controller.currentTeam.value == "A" ? teamAColor : teamBColor);

      return Scaffold(
        body: Column(
          children: [
            ClipPath(
              clipper: HeaderClipper(),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 40),
                decoration: BoxDecoration(color: activeColor),
                child: Stack(
                  children: [
                    Center(
                      child: Text(
                        headerText,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Positioned(
                      right: 16,
                      bottom: -4,
                      child: IconButton(
                        onPressed: showBluetoothDevices,
                        icon: Icon(
                          Icons.bluetooth,
                          color: controller.isConnected.value
                              ? Colors.blue
                              : Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16.0),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16.0),
                        border: Border.all(color: activeColor, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withOpacity(0.4),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Text(
                        question["question"],
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 15),
                    ...question["options"].asMap().entries.map<Widget>((entry) {
                      int index = entry.key;
                      String option = entry.value;

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: ElevatedButton(
                          onPressed: controller.isPaused.value
                              ? null
                              : () => checkAnswer(option),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16.0),
                            backgroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30.0),
                              side: BorderSide(color: activeColor),
                            ),
                          ),
                          child: Row(
                            children: [
                              const SizedBox(width: 10),
                              CircleAvatar(
                                backgroundColor: activeColor,
                                child: Text(
                                  optionLabels[index],
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  option,
                                  style: const TextStyle(
                                      fontSize: 16, color: Colors.black),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                    const SizedBox(height: 10),
                    Text(
                      "Tiempo restante: ${controller.timeLeft.value} segundos",
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8.0),
                      child: LinearProgressIndicator(
                        value: controller.timeLeft.value / 15,
                        minHeight: 10,
                        backgroundColor: Colors.grey.shade300,
                        color: progressBarColor,
                      ),
                    ),
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: ElevatedButton(
                        onPressed: togglePause,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16.0),
                          backgroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30.0),
                            side: BorderSide(color: neutralColor),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircleAvatar(
                              backgroundColor: neutralColor,
                              child: Icon(
                                controller.isPaused.value
                                    ? Icons.play_arrow
                                    : Icons.pause,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              controller.isPaused.value
                                  ? "Iniciar Juego"
                                  : "Pausa",
                              style: const TextStyle(
                                  fontSize: 18, color: Colors.black),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    });
  }
}

class HeaderClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    Path path = Path();
    path.lineTo(0, size.height - 40);
    path.quadraticBezierTo(
        size.width / 2, size.height, size.width, size.height - 40);
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) {
    return false;
  }
}
