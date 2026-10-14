# ⏱️ Gerenciador de Horas e Projetos

> Este reposit?rio cont?m a vers?o **web** do Gerenciador de Horas. O sistema execut?vel ? mantido separadamente.
> C?digo, testes e integra??o local est?o inclu?dos; credenciais, perfis de navegador, backups e bin?rios gerados ficam fora do Git.

Sistema desenvolvido para **gerenciamento de projetos, controle de horas, tarefas e acompanhamento de serviços**, com foco em organização, produtividade e acompanhamento das atividades realizadas.

O projeto está sendo desenvolvido em **Flutter e Dart**, utilizando **Firebase Authentication e Cloud Firestore** para autenticação e persistência dos dados.

> Projeto desenvolvido por **Rodrigo Zaparolli** como parte da minha formação em **Análise e Desenvolvimento de Sistemas**.

---

## 📌 Sobre o projeto

O **Gerenciador de Horas e Projetos** foi desenvolvido para centralizar informações relacionadas ao acompanhamento de trabalhos e serviços em uma única aplicação.

A proposta é permitir que o usuário organize seus projetos, acompanhe prazos, registre horas trabalhadas, gerencie tarefas e consulte informações por meio de uma interface visual e centralizada.

O sistema também conta com recursos voltados para análise e acompanhamento das atividades, buscando facilitar a gestão do trabalho realizado.

---

## 🚀 Funcionalidades

### 📁 Gerenciamento de projetos

* Cadastro de novos projetos e trabalhos
* Edição de projetos existentes
* Organização das informações do trabalho
* Controle de status
* Definição de datas e prazos
* Estimativa de horas
* Associação de clientes e serviços
* Identificação de responsáveis
* Organização de trabalhos internos do serviço
* Alertas visuais relacionados a prazos

### ⏱️ Controle de horas

* Início de cronômetro para atividades
* Pausa do cronômetro
* Encerramento do cronômetro
* Registro das horas trabalhadas
* Associação do registro ao projeto ou tarefa
* Controle dos registros realizados
* Visualização do tempo trabalhado

### ✅ Tarefas e atividades

* Organização das tarefas executadas
* Associação de tarefas aos trabalhos
* Acompanhamento das atividades
* Controle de execução
* Checklist de atividades

### 📊 Métricas

O sistema possui uma área destinada ao acompanhamento das informações através de indicadores e gráficos.

Entre os recursos estão:

* Visualização de horas
* Acompanhamento de atividades
* Análise dos trabalhos
* Gráficos para facilitar a interpretação dos dados

### 📋 Projetos finalizados

Área destinada à organização e consulta dos trabalhos concluídos.

### 👤 Usuário

* Autenticação através do Firebase
* Identificação do usuário
* Perfil do usuário
* Imagem de perfil
* Persistência das informações

### 📄 Documentos e arquivos

O projeto possui recursos para trabalhar com arquivos e documentos utilizados durante o gerenciamento dos trabalhos.

Também possui suporte para:

* Seleção de arquivos
* Abertura de caminhos de arquivos
* Geração de PDF
* Impressão de documentos

---

## 🛠️ Tecnologias utilizadas

### Front-end

* **Flutter**
* **Dart**
* Material Design

### Backend / Serviços

* **Firebase**
* **Firebase Authentication**
* **Cloud Firestore**

### Bibliotecas e recursos

* `fl_chart` — gráficos
* `file_picker` — seleção de arquivos
* `image_picker` — seleção de imagens
* `path_provider` — acesso a diretórios do sistema
* `url_launcher` — abertura de links e caminhos
* `pdf` — geração de documentos PDF
* `printing` — impressão
* `package_info_plus` — informações da aplicação
* `flutter_launcher_icons` — geração dos ícones da aplicação

As dependências principais estão declaradas no `pubspec.yaml` do projeto.

---

## 🏗️ Estrutura do projeto

A aplicação segue uma organização baseada na separação de responsabilidades entre interface, modelos, serviços e funcionalidades.

```text
Gerenciador_Horas/
│
├── android/
├── ios/
├── linux/
├── macos/
├── web/
├── windows/
│
├── assets/
│   └── images/
│
├── lib/
│   ├── app/
│   ├── core/
│   ├── data/
│   ├── domain/
│   ├── features/
│   ├── shared/
│   └── main.dart
│
├── test/
│
├── installer/
│
├── firebase.json
├── pubspec.yaml
├── pubspec.lock
├── analysis_options.yaml
└── README.md
```

A estrutura do repositório também inclui arquivos específicos para o instalador e os diferentes ambientes suportados pelo Flutter.

---

## 🔥 Firebase

O projeto utiliza o Firebase como infraestrutura para serviços de autenticação e armazenamento dos dados.

### Firebase Authentication

Responsável pelo processo de autenticação dos usuários.

### Cloud Firestore

Utilizado para persistência dos dados da aplicação, incluindo informações relacionadas aos usuários, projetos, trabalhos e registros de horas.

### Firebase Storage

Os anexos no Storage são habilitados com `--dart-define=PROJECT_STORAGE_ENABLED=true`, após configurar o bucket e publicar `storage.rules`. Sem essa opção, use links compartilhados para arquivos e pastas. A prévia Excel também funciona selecionando uma planilha XLSX no navegador, sem precisar de armazenamento na nuvem ou Python.

> As configurações específicas do Firebase não devem ser expostas publicamente. Antes de executar o projeto, é necessário configurar o ambiente Firebase correspondente.

---

## 💻 Plataformas

O projeto possui estrutura Flutter preparada para diferentes plataformas:

| Plataforma | Suporte |
| ---------- | ------- |
| 🪟 Windows | ✅       |
| 🤖 Android | ✅       |
| 🍎 iOS     | ✅       |
| 🌐 Web     | ✅       |
| 🐧 Linux   | ✅       |
| 🍎 macOS   | ✅       |

O foco atual do desenvolvimento está especialmente voltado para a utilização em **Windows**, incluindo estrutura para criação de instalador da aplicação.

---

## ⚙️ Requisitos

Para executar o projeto localmente, recomenda-se ter instalado:

* Flutter
* Dart
* Android Studio ou Visual Studio
* Git
* Conta/projeto no Firebase

Versão do SDK Dart utilizada pelo projeto:

```text
>=3.5.0 <4.0.0
```

A versão atualmente definida no `pubspec.yaml` é `1.0.0+1`.

---

## 📥 Instalação

### 1. Clone o repositório

```bash
git clone https://github.com/Rodrigo-Zaparolli/Gerenciador_Horas.git
```

Entre na pasta:

```bash
cd Gerenciador_Horas
```

### 2. Instale as dependências

```bash
flutter pub get
```

### 3. Configure o Firebase

Configure o projeto Firebase de acordo com o ambiente em que a aplicação será executada.

Depois confira se os arquivos de configuração necessários estão corretamente configurados.

### 4. Execute a aplicação

Para verificar os dispositivos disponíveis:

```bash
flutter devices
```

Para executar no Windows:

```bash
flutter run -d windows
```

Para executar no Android:

```bash
flutter run
```

---

## 🪟 Executando no Windows

O projeto possui suporte específico para Windows.

Para gerar uma versão de produção:

```bash
flutter build windows
```

Os arquivos gerados podem ser encontrados na estrutura de build do Flutter.

O projeto também possui uma pasta `installer`, utilizada durante o processo de preparação do instalador para Windows.

---

## 🌐 Executando na Web

A versão web, os serviços opcionais e o comando para abrir o pacote pronto estão documentados em [WEB.md](WEB.md).

Para iniciar a aplicação em um navegador durante o desenvolvimento:

```bash
flutter run -d chrome
```

Para gerar os arquivos de produção:

```bash
flutter build web --release
```

Os arquivos gerados ficam em `build/web`. A configuração publica arquivos estáticos no Firebase Hosting; as regras do Storage podem ser publicadas separadamente com `--only storage`. As chamadas E-Desk usam o endereço configurado em `EDESK_API_URL`.

### Publicação sem faturamento

A compilação padrão usa login e Firestore sem habilitar uploads ou um servidor E-Desk. Os serviços do Firebase permanecem sujeitos às cotas e à configuração do projeto.

```bash
flutter build web --release
firebase deploy --only hosting --project gerenciador-horas
```

Na compilação padrão, é possível informar links externos compartilhados para arquivos e pastas e gerar a prévia de Excel selecionando um arquivo XLSX local. Anexos persistentes exigem um Storage configurado; a automação E-Desk exige um backend configurado. O código não ativa serviços ou faturamento automaticamente.

O deploy do Hosting não publica o serviço Cloud Run e não requer o Google Cloud CLI.

### Automação E-Desk no navegador

A versão web pode conectar-se ao backend existente em `cloud_run/main.py`.
Após disponibilizar esse servidor, informe sua URL base na execução ou compilação:

```bash
flutter run -d chrome --dart-define=EDESK_API_URL=https://seu-servidor.example.com
flutter build web --release --dart-define=EDESK_API_URL=https://seu-servidor.example.com
```

O cliente envia o token do usuário autenticado no Firebase e chama as rotas
`/api/edesk/comentarios`, `/api/edesk/fases` e `/api/edesk/horas`. O servidor deve
conseguir validar tokens do projeto Firebase e executar os scripts com Playwright.
Configure `EDESK_API_ORIGINS` no servidor com a origem do site se utilizar outro
domínio; as origens do Firebase Hosting deste projeto e localhost já são aceitas.
HTTPS é obrigatório para servidores remotos. HTTP é permitido apenas em
`localhost` e `127.0.0.1` para desenvolvimento.

Sem `EDESK_API_URL`, a automação informa que o servidor precisa ser configurado;
as demais funcionalidades continuam usando Firebase. O navegador não executa
Python nem abre caminhos locais do Windows: use links compartilhados para
pastas e planilhas. O aviso de atualização do instalador Windows é desativado
na web. Os arquivos compilados ficam em `build/web` e devem ser servidos por HTTP
ou HTTPS, sem abrir `index.html` diretamente pelo explorador de arquivos.

---

## 📸 Interface

A aplicação possui uma interface desenvolvida especificamente para facilitar a visualização e organização das principais funcionalidades.

Entre os módulos presentes estão:

* Gestão de Horas e Projetos
* Cadastro de Trabalho
* Métricas
* Projetos Finalizados
* Orientações
* Tarefas Executadas
* Checklist
* Solicitações

Os elementos visuais utilizados pela aplicação estão organizados na pasta:

```text
assets/images/
```

incluindo os logotipos e ícones utilizados na interface.

> **Em breve:** imagens e demonstrações das principais telas serão adicionadas nesta seção.

---

## 🧠 Arquitetura e organização

O projeto foi estruturado buscando manter uma separação entre:

* Interface do usuário
* Regras de negócio
* Modelos de dados
* Serviços
* Persistência
* Funcionalidades específicas

Essa organização facilita a manutenção do código e permite que novas funcionalidades sejam adicionadas de forma mais estruturada.

---

## 📈 Evolução do projeto

O projeto está em desenvolvimento contínuo.

Algumas das etapas realizadas durante sua construção incluem:

* Estruturação inicial do aplicativo Flutter
* Criação da navegação principal
* Desenvolvimento da interface
* Integração com Firebase
* Implementação de autenticação
* Persistência de dados no Firestore
* Cadastro e gerenciamento de projetos
* Implementação do controle de horas
* Criação do cronômetro
* Desenvolvimento de tarefas
* Desenvolvimento de checklist
* Criação de métricas
* Organização de projetos finalizados
* Implementação de recursos para arquivos
* Geração de documentos PDF
* Preparação para execução no Windows
* Criação da estrutura de instalação da aplicação

---

## 🎯 Objetivos do projeto

O projeto tem como principais objetivos:

* Centralizar o gerenciamento de projetos e trabalhos;
* Facilitar o registro das horas trabalhadas;
* Melhorar o acompanhamento das tarefas;
* Auxiliar no controle de prazos;
* Disponibilizar informações de forma visual;
* Reduzir a necessidade de controles manuais;
* Aplicar na prática conhecimentos adquiridos durante a formação acadêmica.

---

## 🎓 Projeto acadêmico

Este projeto também representa uma aplicação prática dos conhecimentos adquiridos durante a graduação em **Análise e Desenvolvimento de Sistemas**.

Durante seu desenvolvimento são aplicados conceitos relacionados a:

* Engenharia de software
* Desenvolvimento de aplicações
* Programação orientada a objetos
* Arquitetura de software
* Banco de dados
* Desenvolvimento multiplataforma
* APIs e serviços em nuvem
* Autenticação
* Persistência de dados
* Interface de usuário
* Versionamento de código

---

## 🔐 Segurança

Informações sensíveis e credenciais de serviços externos não devem ser armazenadas diretamente no código-fonte ou disponibilizadas publicamente.

Antes de publicar alterações no projeto, certifique-se de que arquivos contendo:

* chaves privadas;
* credenciais;
* senhas;
* tokens;
* configurações sensíveis;

não estejam sendo enviados para o repositório.

---

## 🗺️ Próximos passos

Algumas melhorias planejadas para o projeto incluem:

* [ ] Melhorias contínuas na interface
* [ ] Aperfeiçoamento das métricas
* [ ] Evolução do sistema de notificações e alertas
* [ ] Melhorias no gerenciamento de tarefas
* [ ] Ampliação dos relatórios
* [ ] Melhorias na experiência do usuário
* [ ] Aperfeiçoamento do instalador Windows
* [ ] Criação de documentação técnica mais detalhada
* [ ] Inclusão de screenshots e demonstrações
* [ ] Publicação de versões/releases do aplicativo

---

## 📌 Status

🚧 **Em desenvolvimento**

O projeto encontra-se em evolução e novas funcionalidades e melhorias são adicionadas continuamente.

---

## 👨‍💻 Desenvolvedor

**Rodrigo Zaparolli**

Estudante de **Análise e Desenvolvimento de Sistemas**, com interesse em desenvolvimento de software, aplicações multiplataforma, Flutter, Dart, Firebase e desenvolvimento de sistemas.

### 🌐 Links

* GitHub: [Rodrigo-Zaparolli](https://github.com/Rodrigo-Zaparolli)
* Projeto web: [Gerenciador_Horas_Web](https://github.com/Rodrigo-Zaparolli/Gerenciador_Horas_Web)

---

## 📄 Licença

Este projeto está em desenvolvimento para fins acadêmicos e de portfólio.

Consulte o proprietário do repositório antes de reutilizar, distribuir ou modificar o código para outras finalidades.

---

⭐ **Se este projeto foi útil ou interessante para você, considere deixar uma estrela no repositório.**

---

<p align="center">
  Desenvolvido com ❤️ utilizando Flutter e Dart
</p>
