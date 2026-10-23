import sys
import os
import json
import base64
import re
import time
import tempfile

from pathlib import Path


# ============================================================
# CONFIGURAÇÃO
# ============================================================

DEFAULT_SHEET = "Dados"
DEFAULT_RANGE = "AG5:AL11"

# Constantes usadas pela automação COM do Microsoft Excel.
XL_SCREEN = 1
XL_PICTURE = -4147
XL_BITMAP = 2


# ============================================================
# LOG
# ============================================================

def log(msg):
    print(
        f"[ExcelPreview] {msg}",
        file=sys.stderr,
        flush=True,
    )


# ============================================================
# RESPOSTA PARA O FLUTTER
# ============================================================

def enviar_resposta(dados):
    print(
        json.dumps(
            dados,
            ensure_ascii=False,
        ),
        flush=True,
    )


# ============================================================
# REFERÊNCIA EXCEL
# ============================================================

def interpretar_referencia(referencia):
    """
    Aceita referências como:
      ='CRONOGRAMAS'!$B$27:$L$34
      CRONOGRAMAS!B27:L34
      B27:L34
    """

    texto = str(referencia or "").strip()

    if texto.startswith("="):
        texto = texto[1:]

    sheet = DEFAULT_SHEET
    endereco = texto or DEFAULT_RANGE

    if "!" in endereco:
        sheet, endereco = endereco.rsplit("!", 1)

        sheet = (
            sheet
            .strip()
            .strip("'")
            .replace("''", "'")
        )

    endereco = (
        endereco
        .replace("$", "")
        .strip()
        .upper()
    )

    if not re.fullmatch(
        r"[A-Z]{1,3}\d+:[A-Z]{1,3}\d+",
        endereco,
    ):
        raise ValueError(
            f"Intervalo inválido: {referencia}"
        )

    return (
        sheet or DEFAULT_SHEET,
        endereco,
    )


# ============================================================
# DIRETÓRIO DE TRABALHO / DEBUG
# ============================================================

def resolver_nome_aba(nome_aba, abas):
    """Preserve exact sheet choices; support the confirmed legacy Maker name."""
    requested = str(nome_aba).strip().casefold()
    exact = [name for name in abas if str(name).strip().casefold() == requested]
    if len(exact) == 1:
        return exact[0]
    if requested == 'professional checklist-processo' and not exact:
        maker = [name for name in abas if str(name).strip().casefold() == 'maker checklist-processo']
        if len(maker) == 1:
            return maker[0]
    raise ValueError(f"Aba '{nome_aba}' não encontrada. Abas disponíveis: {', '.join(abas)}")


def obter_diretorio_debug():
    """
    O aplicativo instalado pode estar em Program Files.
    Por isso arquivos temporários/debug ficam no LocalAppData.
    """

    local_app_data = Path(
        os.environ.get(
            "LOCALAPPDATA",
            str(
                Path.home()
                / "AppData"
                / "Local"
            ),
        )
    )

    diretorio = (
        local_app_data
        / "Gerenciador de Horas"
        / "edesk_bot"
        / "debug"
    )

    diretorio.mkdir(
        parents=True,
        exist_ok=True,
    )

    return diretorio


# ============================================================
# MICROSOFT EXCEL -> IMAGEM REAL DO INTERVALO
# ============================================================

def renderizar_intervalo_excel(
    caminho_arquivo,
    nome_aba,
    endereco,
):
    """
    Renderiza o intervalo usando o próprio Microsoft Excel.

    O Excel executa Range.CopyPicture(), preservando a aparência real
    do intervalo. Em vez de usar Chart.Paste() (que falha em algumas
    versões/instalações do Excel), capturamos diretamente do Clipboard
    do Windows a imagem produzida pelo Excel e a convertemos para PNG.
    """

    try:
        import pythoncom
        import win32com.client
        import win32clipboard
        import win32con
    except ImportError as erro:
        raise RuntimeError(
            "A integração com o Microsoft Excel requer pywin32."
        ) from erro

    try:
        from PIL import Image
    except ImportError as erro:
        raise RuntimeError(
            "A captura da imagem do Excel requer Pillow."
        ) from erro

    caminho_arquivo = Path(caminho_arquivo).resolve()

    if not caminho_arquivo.exists():
        raise FileNotFoundError(
            f"Arquivo não encontrado: {caminho_arquivo}"
        )

    def ler_dib_do_clipboard():
        """
        Lê CF_DIB/CF_DIBV5 do Clipboard e monta um BMP temporário
        válido para o Pillow. Não redesenha a planilha: apenas converte
        a imagem que o próprio Excel colocou no Clipboard.
        """
        dados = None

        win32clipboard.OpenClipboard()
        try:
            formatos = []

            if win32clipboard.IsClipboardFormatAvailable(win32con.CF_DIB):
                formatos.append(win32con.CF_DIB)

            # CF_DIBV5 = 17. Nem toda versão do pywin32 expõe a constante.
            cf_dibv5 = getattr(win32con, "CF_DIBV5", 17)
            if win32clipboard.IsClipboardFormatAvailable(cf_dibv5):
                formatos.append(cf_dibv5)

            for formato in formatos:
                try:
                    candidato = win32clipboard.GetClipboardData(formato)
                    if isinstance(candidato, (bytes, bytearray)) and candidato:
                        dados = bytes(candidato)
                        break
                except Exception:
                    continue
        finally:
            win32clipboard.CloseClipboard()

        if not dados:
            return None

        # O CF_DIB não contém o cabeçalho BITMAPFILEHEADER (14 bytes).
        # Calculamos o offset dos pixels a partir do cabeçalho DIB.
        import struct
        import io

        if len(dados) < 40:
            return None

        header_size = struct.unpack_from("<I", dados, 0)[0]

        if header_size < 40 or len(dados) < header_size:
            return None

        bit_count = struct.unpack_from("<H", dados, 14)[0]
        compression = struct.unpack_from("<I", dados, 16)[0]
        clr_used = struct.unpack_from("<I", dados, 32)[0]

        palette_size = 0
        if bit_count <= 8:
            palette_entries = clr_used if clr_used else (1 << bit_count)
            palette_size = palette_entries * 4

        # BI_BITFIELDS pode trazer três máscaras RGB após BITMAPINFOHEADER.
        masks_size = 0
        if header_size == 40 and compression == 3:
            masks_size = 12

        pixel_offset = 14 + header_size + masks_size + palette_size
        file_size = 14 + len(dados)

        bmp_header = (
            b"BM"
            + struct.pack("<I", file_size)
            + b"\x00\x00\x00\x00"
            + struct.pack("<I", pixel_offset)
        )

        bmp_bytes = bmp_header + dados
        imagem = Image.open(io.BytesIO(bmp_bytes))
        imagem.load()

        return imagem

    pythoncom.CoInitialize()

    excel = None
    workbook = None
    clipboard_original = None
    clipboard_saved = False
    clipboard_sequence = None

    try:
        clipboard_original = pythoncom.OleGetClipboard()
        clipboard_saved = True
        log(
            "Abrindo Microsoft Excel em segundo plano "
            "para renderização real do intervalo."
        )

        try:
            excel = win32com.client.DispatchEx('Excel.Application')
        except Exception as error:
            raise RuntimeError('Não foi possível iniciar o Microsoft Excel neste computador. Abra o Excel manualmente e conclua eventuais telas de ativação ou configuração; depois tente novamente.') from error

        excel.Visible = False
        excel.DisplayAlerts = False
        excel.ScreenUpdating = True
        excel.EnableEvents = False
        excel.AskToUpdateLinks = False
        excel.AutomationSecurity = 3

        try:
            workbook = excel.Workbooks.Open(
                str(caminho_arquivo),
                UpdateLinks=0,
                ReadOnly=True,
                IgnoreReadOnlyRecommended=True,
                AddToMru=False,
            )
        except Exception as error:
            raise RuntimeError('O Excel iniciou, mas não conseguiu abrir a planilha vinculada. Confira se o arquivo está disponível neste PC e se exige senha ou está bloqueado.') from error

        abas = [str(workbook.Worksheets(i).Name) for i in range(1, workbook.Worksheets.Count + 1)]
        nome_resolvido = resolver_nome_aba(nome_aba, abas)
        worksheet = workbook.Worksheets(nome_resolvido)

        worksheet.Activate()
        try:
            intervalo = worksheet.Range(endereco)
        except Exception as error:
            raise RuntimeError(f'O Excel abriu a guia {nome_aba}, mas não conseguiu acessar o intervalo {endereco}. Confira o campo Tabela do Excel.') from error

        log(
            "Renderizando pelo Excel: "
            f"{worksheet.Name}!{endereco}"
        )

        # Limpa o Clipboard antes do CopyPicture para garantir que uma
        # imagem antiga nunca seja retornada.
        try:
            win32clipboard.OpenClipboard()
            try:
                win32clipboard.EmptyClipboard()
                clipboard_sequence = win32clipboard.GetClipboardSequenceNumber()
            finally:
                win32clipboard.CloseClipboard()
        except Exception as erro:
            log(f"Aviso ao limpar Clipboard: {erro}")

        ultimo_erro = None
        imagem = None

        # O Clipboard do Office é assíncrono. Fazemos poucas tentativas,
        # sempre pedindo ao Excel a imagem real do mesmo Range.
        for tentativa in range(1, 7):
            try:
                # Pedimos ao próprio Excel uma cópia raster (xlBitmap).
                # No Microsoft 365, xlPicture normalmente publica EMF/metafile,
                # enquanto xlBitmap disponibiliza a imagem em formato DIB,
                # que conseguimos capturar sem redesenhar a tabela.
                intervalo.CopyPicture(
                    Appearance=XL_SCREEN,
                    Format=XL_BITMAP,
                )
                clipboard_sequence = win32clipboard.GetClipboardSequenceNumber()

                # Dá tempo para o Excel publicar CF_DIB no Clipboard.
                time.sleep(0.25 + (tentativa * 0.10))

                imagem = ler_dib_do_clipboard()

                if imagem is not None:
                    clipboard_sequence = win32clipboard.GetClipboardSequenceNumber()
                    ultimo_erro = None
                    log(
                        "Imagem real do Excel capturada diretamente "
                        f"do Clipboard na tentativa {tentativa}."
                    )
                    break

                ultimo_erro = RuntimeError(
                    "Excel copiou o intervalo, mas CF_DIB ainda "
                    "não estava disponível no Clipboard."
                )

            except Exception as erro:
                ultimo_erro = erro
                log(
                    "Aguardando imagem do Excel no Clipboard "
                    f"(tentativa {tentativa}/6): {erro}"
                )

            time.sleep(0.20)

        if imagem is None:
            formatos_clipboard = []
            try:
                win32clipboard.OpenClipboard()
                try:
                    formato = 0
                    while True:
                        formato = win32clipboard.EnumClipboardFormats(formato)
                        if not formato:
                            break
                        try:
                            nome = win32clipboard.GetClipboardFormatName(formato)
                        except Exception:
                            nome = ""
                        formatos_clipboard.append(
                            f"{formato}{f' ({nome})' if nome else ''}"
                        )
                finally:
                    win32clipboard.CloseClipboard()
            except Exception as erro_formatos:
                formatos_clipboard.append(
                    f"erro ao enumerar: {erro_formatos}"
                )

            raise RuntimeError(
                "O Excel não conseguiu disponibilizar a imagem "
                f"do intervalo como bitmap no Clipboard: {ultimo_erro}. "
                "Formatos disponíveis: "
                + ", ".join(formatos_clipboard)
            )

        # Converte somente o bitmap produzido pelo Excel para PNG.
        # Nenhuma célula/formatação é reconstruída pelo Python.
        import io

        if imagem.mode not in ("RGB", "RGBA"):
            imagem = imagem.convert("RGBA")

        buffer_png = io.BytesIO()
        imagem.save(
            buffer_png,
            format="PNG",
        )
        png = buffer_png.getvalue()

        if not png:
            raise RuntimeError(
                "A imagem capturada do Excel ficou vazia."
            )

        log(
            "Imagem real do Excel: "
            f"{imagem.width}x{imagem.height} "
            f"({len(png)} bytes)"
        )

        imagem_base64 = (
            base64
            .b64encode(png)
            .decode("utf-8")
        )

        return (
            imagem_base64,
            str(worksheet.Name),
        )

    finally:
        try:
            restore_clipboard = clipboard_saved and clipboard_sequence == win32clipboard.GetClipboardSequenceNumber()
        except Exception:
            restore_clipboard = False
        if restore_clipboard:
            try:
                pythoncom.OleSetClipboard(clipboard_original)
                pythoncom.OleFlushClipboard()
            except Exception:
                pass
        if workbook is not None:
            try:
                workbook.Close(
                    SaveChanges=False
                )
            except Exception:
                pass

        if excel is not None:
            try:
                excel.CutCopyMode = False
            except Exception:
                pass

            try:
                excel.Quit()
            except Exception:
                pass

        pythoncom.CoUninitialize()


# ============================================================
# MAIN
# ============================================================

def main():
    """
    Mantém o mesmo protocolo JSON já usado pelo Flutter:
      open    -> abre arquivo e gera preview
      refresh -> gera novamente usando arquivo já aberto
      close   -> encerra o processo

    Portanto o Flutter não precisa mudar para usar esta versão.
    """

    log(
        "ExcelPreview iniciado - "
        "RENDERIZAÇÃO NATIVA MICROSOFT EXCEL/COM."
    )

    caminho_atual = None
    sheet_atual = DEFAULT_SHEET
    range_atual = DEFAULT_RANGE

    for linha in sys.stdin:
        linha = linha.strip()

        if not linha:
            continue

        try:
            comando = json.loads(
                linha
            )

            acao = str(
                comando.get(
                    "acao",
                    "",
                )
            ).lower()

            # =================================================
            # CLOSE
            # =================================================

            if acao == "close":
                enviar_resposta({
                    "ok": True,
                    "acao": "close",
                })
                break

            # =================================================
            # OPEN
            # =================================================

            if acao == "open":
                caminho_atual = Path(
                    str(
                        comando.get(
                            "path"
                        )
                        or ""
                    )
                )

                if not caminho_atual.exists():
                    raise FileNotFoundError(
                        "Arquivo não encontrado: "
                        f"{caminho_atual}"
                    )

            # =================================================
            # VALIDA AÇÃO
            # =================================================

            if acao not in (
                "open",
                "refresh",
            ):
                enviar_resposta({
                    "ok": False,
                    "erro": (
                        "Ação desconhecida: "
                        f"{acao}"
                    ),
                })
                continue

            if caminho_atual is None:
                raise RuntimeError(
                    "Arquivo ainda não foi aberto."
                )

            # =================================================
            # REFERÊNCIA
            # =================================================

            referencia = (
                comando.get(
                    "intervalo"
                )
                or comando.get(
                    "range"
                )
                or comando.get(
                    "rangeAddress"
                )
            )

            if referencia:
                (
                    sheet_atual,
                    range_atual,
                ) = interpretar_referencia(
                    referencia
                )

            log(
                "Arquivo: "
                f"{caminho_atual}"
            )

            log(
                "Intervalo: "
                f"{sheet_atual}!"
                f"{range_atual}"
            )

            # =================================================
            # RENDERIZA COM O PRÓPRIO MICROSOFT EXCEL
            # =================================================

            (
                imagem_base64,
                nome_real_aba,
            ) = renderizar_intervalo_excel(
                caminho_atual,
                sheet_atual,
                range_atual,
            )

            sheet_atual = (
                nome_real_aba
            )

            # =================================================
            # RETORNO PARA FLUTTER
            # =================================================

            enviar_resposta({
                "ok": True,
                "acao": acao,
                "imagemBase64": (
                    imagem_base64
                ),
                "sheet": (
                    sheet_atual
                ),
                "range": (
                    range_atual
                ),
            })

            log(
                "Preview real do Excel "
                "gerado com sucesso."
            )

        except Exception as erro:
            log(
                "ERRO: "
                f"{type(erro).__name__}: "
                f"{erro}"
            )

            enviar_resposta({
                "ok": False,
                "erro": str(
                    erro
                ),
            })

    log(
        "ExcelPreview finalizado."
    )


# ============================================================
# EXECUÇÃO
# ============================================================

if __name__ == "__main__":
    main()
