enum EdeskOperation {
  hours,
  comment,
  phases,
  percentage;

  static EdeskOperation? fromScript(String script) => switch (script) {
        'edesk_horas.py' => hours,
        'edesk_comentario.py' => comment,
        'edesk_fases.py' => phases,
        'edesk_percentual.py' => percentage,
        _ => null,
      };

  String successMessage({bool includesPercentage = false}) => switch (this) {
        hours => 'Horas cadastradas no E-Desk. Envio finalizado com sucesso.',
        comment when includesPercentage =>
          'Comentário e porcentagem cadastrados no E-Desk. Envio finalizado com sucesso.',
        comment =>
          'Comentário cadastrado no E-Desk. Envio finalizado com sucesso.',
        phases => 'Fases atualizadas no E-Desk. Envio finalizado com sucesso.',
        percentage =>
          'Porcentagem cadastrada no E-Desk. Envio finalizado com sucesso.',
      };
}
