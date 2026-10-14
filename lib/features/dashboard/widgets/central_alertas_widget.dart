import 'package:gerenciador_horas/domain/models/deadline_alert.dart';
import 'package:gerenciador_horas/core/theme/app_appearance.dart';
import 'package:gerenciador_horas/core/theme/app_palette.dart';
import 'package:flutter/material.dart';
import 'package:gerenciador_horas/domain/models/project_model.dart';

class CentralAlertasWidget extends StatelessWidget {
  final List<ProjectModel> projects;
  final String Function(DateTime) formatDateShort;

  const CentralAlertasWidget({
    super.key,
    required this.projects,
    required this.formatDateShort,
  });

  @override
  Widget build(BuildContext context) {
    AppAppearance.watch(context);
    final alertItems = DeadlineAlert.collect(projects, DateTime.now());

    return Container(
      decoration: BoxDecoration(
        color: AppPalette.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppPalette.text.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ============================================================
          // CABEÇALHO
          // ============================================================
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            decoration: BoxDecoration(
              color: AppPalette.surface,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
              border: Border(
                bottom: BorderSide(
                  color: AppPalette.text.withValues(alpha: 0.08),
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Projetos com datas a vencer nos próximos dias',
                  style: TextStyle(
                    color: AppPalette.text,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                Text(
                  '(${alertItems.length} alertas)',
                  style: TextStyle(
                    color: AppPalette.secondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),

          // ============================================================
          // LISTA DE ALERTAS
          // ============================================================
          alertItems.isEmpty
              ? Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'Nenhum projeto ou etapa com prazo crítico no momento. Tudo em ordem!',
                      style: TextStyle(
                        color: AppPalette.secondary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                )
              : ListView.builder(
                  primary: false,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: alertItems.length,
                  itemBuilder: (context, index) {
                    final item = alertItems[index];

                    // Vermelho se já passou do prazo.
                    // Laranja se ainda está dentro do prazo crítico.
                    final bool isAtrasado = item.differenceDays < 0;

                    final Color rowBgColor =
                        index % 2 == 0 ? AppPalette.field : AppPalette.surface;

                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: rowBgColor,
                        border: Border(
                          bottom: BorderSide(
                            color: AppPalette.text.withValues(alpha: 0.04),
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          // ==================================================
                          // ID
                          // ==================================================
                          SizedBox(
                            width: 70,
                            child: Text(
                              item.id,
                              style: TextStyle(
                                color: AppPalette.secondary,
                                fontSize: 11,
                              ),
                            ),
                          ),

                          // ==================================================
                          // Nº
                          // ==================================================
                          SizedBox(
                            width: 40,
                            child: Text(
                              item.id2,
                              style: TextStyle(
                                color: AppPalette.secondary,
                                fontSize: 11,
                              ),
                            ),
                          ),

                          // ==================================================
                          // CLIENTE
                          // ==================================================
                          Expanded(
                            flex: 3,
                            child: Text(
                              item.client,
                              style: TextStyle(
                                color: AppPalette.text,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),

                          // ==================================================
                          // TIPO DE SERVIÇO
                          // ==================================================
                          Expanded(
                            flex: 2,
                            child: Text(
                              item.serviceType,
                              style: TextStyle(
                                color: AppPalette.secondary,
                                fontSize: 11,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),

                          // ==================================================
                          // ETAPA
                          // ==================================================
                          Expanded(
                            flex: 2,
                            child: Text(
                              item.stage,
                              style: TextStyle(
                                color: AppPalette.secondary,
                                fontSize: 11,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),

                          // ==================================================
                          // DATA INICIAL
                          // ==================================================
                          SizedBox(
                            width: 90,
                            child: Text(
                              formatDateShort(item.planStart),
                              style: TextStyle(
                                color: AppPalette.secondary,
                                fontSize: 11,
                              ),
                            ),
                          ),

                          // ==================================================
                          // DATA FINAL
                          // ==================================================
                          Container(
                            width: 90,
                            padding: const EdgeInsets.symmetric(
                              vertical: 2,
                              horizontal: 6,
                            ),
                            decoration: BoxDecoration(
                              color: isAtrasado
                                  ? const Color(0xFFB71C1C)
                                  : const Color(0xFFF57F17),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              formatDateShort(item.planEnd),
                              style: TextStyle(
                                color: AppPalette.text,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),

                          const SizedBox(width: 12),

                          // ==================================================
                          // STATUS
                          // ==================================================
                          Container(
                            width: 70,
                            padding: const EdgeInsets.symmetric(
                              vertical: 2,
                              horizontal: 6,
                            ),
                            decoration: BoxDecoration(
                              color: isAtrasado
                                  ? const Color(0xFF880E4F)
                                  : const Color(0xFFEF6C00),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              isAtrasado ? 'Atrasado' : 'Ativo',
                              style: TextStyle(
                                color: AppPalette.text,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ],
      ),
    );
  }
}
