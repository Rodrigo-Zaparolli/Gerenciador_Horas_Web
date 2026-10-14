A integração local recebia EDESK_DATA_DIR temporário por operação, incluindo o perfil Chromium. Horas agora usa EDESK_PROFILE_DIR separado, com diretório persistente identificado pelo hash de UID e e-mail E-Desk. Cookies de sessão também são preservados antes de fechar o navegador. Request, eventos e progresso permanecem temporários. Cloud Run conserva isolamento temporário.

A pausa fixa de 4 segundos ao carregar a lista foi substituída por espera do campo de pesquisa visível. Confirmações de salvamento e regras contra duplicidade permanecem.

Ativação: baixar o pacote completo atualizado e executar Iniciar integração E-Desk.cmd. Versão session-profile-3. O iniciador preserva dados e não troca a integração durante um envio. Primeiro login ou sessão expirada pode exigir autenticação. Não houve envio real de horas nem medição de tempo do serviço externo; o ganho depende da rede e da validade da sessão.
