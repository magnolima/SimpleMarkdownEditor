{
	SME - Simple Markdown Editor v1.0.1
	This is a simple markdown editor without any grand pretensions :)

	2026 by Magno Lima - https://github.com/magnolima

}
unit SimpleMarkdownEditor.gui;

interface

uses
	System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
	FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs, FMX.Memo.Types, FMX.StdCtrls, FMX.ScrollBox, FMX.Memo,
	FMX.Controls.Presentation, FMX.WebBrowser, MarkdownProcessor, System.Net.HttpClient, System.NetEncoding,
	System.Net.HttpClientComponent, System.IOUtils, FMX.Platform, System.StrUtils, System.IniFiles, System.ImageList,
	FMX.ImgList, FMX.Menus;

type
	TfrmMarkdown = class(TForm)
		WebBrowser1: TWebBrowser;
		StyleBook1: TStyleBook;
		Panel1: TPanel;
		Panel2: TPanel;
		Panel3: TPanel;
		Panel5: TPanel;
		mmEditor: TMemo;
		Splitter1: TSplitter;
		sbOpen: TSpeedButton;
		OpenDialog1: TOpenDialog;
		SaveDialog1: TSaveDialog;
		sbSave: TSpeedButton;
		ToolBar1: TToolBar;
		sbFontSmall: TSpeedButton;
		sbFontBigger: TSpeedButton;
		sbTitle: TSpeedButton;
		sbCode: TSpeedButton;
		SpeedButton2: TSpeedButton;
		SpeedButton4: TSpeedButton;
		SpeedButton5: TSpeedButton;
		SpeedButton6: TSpeedButton;
		MainMenu1: TMainMenu;
		MenuItem1: TMenuItem;
		MenuItem2: TMenuItem;
		MenuItem3: TMenuItem;
		miClose: TMenuItem;
		Timer1: TTimer;
		SpeedButton1: TSpeedButton;
		miNew: TMenuItem;
    sbBold: TSpeedButton;
    Panel6: TPanel;
    sbStrike: TSpeedButton;
    sbItalic: TSpeedButton;
		procedure sbOpenClick(Sender: TObject);
		procedure sbSaveClick(Sender: TObject);
		procedure SpeedButton2Click(Sender: TObject);
		procedure sbFontBiggerClick(Sender: TObject);
		procedure sbFontSmallClick(Sender: TObject);
		procedure sbTitleClick(Sender: TObject);
		procedure sbCodeClick(Sender: TObject);
		procedure FormShow(Sender: TObject);
		procedure FormCreate(Sender: TObject);
		procedure FormClose(Sender: TObject; var Action: TCloseAction);
		procedure miCloseClick(Sender: TObject);
		procedure mmEditorKeyDown(Sender: TObject; var Key: Word; var KeyChar: WideChar; Shift: TShiftState);
		procedure Timer1Timer(Sender: TObject);
		procedure SpeedButton1Click(Sender: TObject);
		procedure WebBrowser1DidFinishLoad(ASender: TObject);
		procedure miNewClick(Sender: TObject);
		procedure mmEditorChangeTracking(Sender: TObject);
		procedure FormActivate(Sender: TObject);
    procedure sbBoldClick(Sender: TObject);
    procedure sbItalicClick(Sender: TObject);
    procedure sbStrikeClick(Sender: TObject);
	private
		FHtmlFontScale: Double;
		FKeyPressed: Boolean;
		FChanged: Boolean;
		FPendingPreviewScroll: Boolean;
		FPendingScrollRatio: Double;
		procedure RefreshPreview;
		procedure ApplyMarkdownHeading(const HeadingLevel: Integer);
		procedure ApplyCodeBlock;
		procedure SaveWindowState;
		procedure LoadWindowState;
		procedure OpenMarkdown(const Filename: string);
		procedure SaveMarkdown;
		function ConfirmSaved: Boolean;
    procedure ApplyTextFormat(memo: TMemo; TextFormat: string);
		{ Private declarations }
	public
		{ Public declarations }
	end;

const
	CONFIG_DIR = '.\config';
	CONFIG_FILE = 'config.ini';
	PROGRAM_NAME = 'Simple Markdown Editor';
	PREVIEW_CARET_ANCHOR_ID = 'sme-current-line';

var
	frmMarkdown: TfrmMarkdown;

implementation

{$R *.fmx}

function PosStrRight(Target, Text: String): Integer;
var
	FoundPos, SearchPos: Integer;
	SearchTarget, SearchText: string;
begin
	Result := 0;
	if Target.IsEmpty or Text.IsEmpty or (Target.Length > Text.Length) then
		Exit;

	SearchTarget := Target.ToLower;
	SearchText := Text.ToLower;
	SearchPos := 1;

	while SearchPos <= SearchText.Length do
	begin
		FoundPos := PosEx(SearchTarget, SearchText, SearchPos);
		if FoundPos = 0 then
			Break;
		Result := FoundPos;
		SearchPos := FoundPos + 1;
	end;
end;

function LoadCSS: String;
const
	HTML_BACKGROUND = '#FFF';
	BASE_FONT_SIZE_EM = 1.0;
var
	scale: Double;
	cssText: string;
	function CssEm(const Value: Double): string;
	begin
		Result := StringReplace(FloatToStr(Value), ',', '.', [rfReplaceAll]) + 'em';
	end;

begin
	if Assigned(frmMarkdown) and (frmMarkdown.FHtmlFontScale > 0) then
		scale := frmMarkdown.FHtmlFontScale
	else
		scale := 1.0;

	cssText := {$I SimpleMarkdownEditor.css};
	cssText := StringReplace(cssText, '%BackgroundColor%', HTML_BACKGROUND, [rfReplaceAll]);
	cssText := StringReplace(cssText, '%BodyFontSize%', CssEm(BASE_FONT_SIZE_EM * scale), [rfReplaceAll]);
	Result := cssText;
end;

function MakeHTML(const css, content: String; const baseUrl: String = ''): String;
begin
	Result := '<!DOCTYPE html><html>'#13'<head>'#13 +
		 '<meta charset="UTF-8"; http-equiv="X-UA-Compatible" content="IE=EmulateIE11">'#13 +
		 '<meta name="viewport" content="width=device-width, initial-scale=1.0">'#13;
	// Inject <base> tag so the browser resolves relative paths (images, etc.)
	if not baseUrl.IsEmpty then
		Result := Result + '<base href="' + baseUrl + '">' + #13;
	Result := Result + '<style>' + css + '</style>' + #13 + '</head>' + #13 + '<body>'#13 + content + #13'</body></html>';
end;

function InjectCaretAnchor(const Input, AnchorId: string; const LineIndex: Integer): string;
var
	Lines: TStringList;
begin
	Result := Input;
	if AnchorId.IsEmpty or (LineIndex < 0) then
		Exit;

	Lines := TStringList.Create;
	try
		Lines.Text := Input;
		if (Lines.Count = 0) or (LineIndex >= Lines.Count) then
			Exit;

		// Insert as a standalone HTML block so markdown tokens on the target line
		// (e.g. # heading, list markers) keep their original meaning.
		Lines.Insert(LineIndex, '<div id="' + AnchorId + '"></div>');
		Result := Lines.Text;
	finally
		Lines.Free;
	end;
end;

function MarkDownToHtml(const Input: string; const baseUrl: String = ''; const CaretLine: Integer = -1): String;
var
	md: TMarkdownProcessor;
	uri, html: String;
begin
	html := InjectCaretAnchor(Input, PREVIEW_CARET_ANCHOR_ID, CaretLine).Trim;
	md := TMarkdownProcessor.createDialect(mdCommonMark);
	try
		try
			html := md.process(html);
		except
			// uncompleted text could raise exception with markdown processor, so we quietly ignore... shhh!
			Exit;
		end;
		html := THTMLEncoding.html.Decode(html);
		uri := 'file:///' + StringReplace(ExtractFilePath(ParamStr(0)), TPath.DirectorySeparatorChar, '/', [rfReplaceAll]);
		html := StringReplace(html, '%uri%', uri, [rfReplaceAll]);
		Result := MakeHTML(LoadCSS(), html, baseUrl);
	finally
		md.Free;
	end;
end;

procedure TfrmMarkdown.LoadWindowState;
var
	IniFile: TIniFile;
	ConfigPath: string;
begin
	ConfigPath := TPath.Combine(ExtractFilePath(ParamStr(0)), CONFIG_DIR);
	if not TDirectory.Exists(ConfigPath) then
		TDirectory.CreateDirectory(ConfigPath);

	IniFile := TIniFile.Create(TPath.Combine(ConfigPath, CONFIG_FILE));
	try
		self.Left := IniFile.ReadInteger('Window', 'Left', 100);
		self.Top := IniFile.ReadInteger('Window', 'Top', 100);
		self.Width := IniFile.ReadInteger('Window', 'Width', 1024);
		self.Height := IniFile.ReadInteger('Window', 'Height', 768);
		if IniFile.ReadString('Window', 'WindowState', 'Normal') = 'Maximized' then
			self.WindowState := TWindowState.wsMaximized;
	finally
		IniFile.Free;
	end;
end;

procedure TfrmMarkdown.miCloseClick(Sender: TObject);
begin
	Close;
end;

procedure TfrmMarkdown.miNewClick(Sender: TObject);
begin
	if ConfirmSaved then
	begin
		mmEditor.Lines.Clear;
		FChanged := False;
		WebBrowser1.Navigate('about:blank');
	end;
end;

function TfrmMarkdown.ConfirmSaved: Boolean;
begin
	Result := true;
	if FChanged then
	begin
		if MessageDlg('File was changed. Save it now?', TMsgDlgType.mtWarning, [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbNo], 0) = mrYes
		then
			SaveMarkdown
		else
			Result := False;
	end;
end;

procedure TfrmMarkdown.mmEditorChangeTracking(Sender: TObject);
begin
	FChanged := true;
end;

procedure TfrmMarkdown.mmEditorKeyDown(Sender: TObject; var Key: Word; var KeyChar: WideChar; Shift: TShiftState);
begin
	if not FKeyPressed then
	begin
		self.Caption := PROGRAM_NAME + ' - ' + OpenDialog1.Filename + '*';
		FKeyPressed := true;
	end;

	// Restart the timer on every keypress so RefreshPreview
	// only triggers after the full idle interval (debounce)
	Timer1.Enabled := False;
	Timer1.Enabled := true;
end;

procedure TfrmMarkdown.SaveWindowState;
var
	IniFile: TIniFile;
	ConfigPath, StateStr: string;
begin
	ConfigPath := TPath.Combine(ExtractFilePath(ParamStr(0)), CONFIG_DIR);
	if not TDirectory.Exists(ConfigPath) then
		TDirectory.CreateDirectory(ConfigPath);

	IniFile := TIniFile.Create(TPath.Combine(ConfigPath, CONFIG_FILE));
	try
		if self.WindowState = TWindowState.wsMaximized then
			StateStr := 'Maximized'
		else
			StateStr := 'Normal';

		IniFile.WriteInteger('Window', 'Left', self.Left);
		IniFile.WriteInteger('Window', 'Top', self.Top);
		IniFile.WriteInteger('Window', 'Width', self.Width);
		IniFile.WriteInteger('Window', 'Height', self.Height);
		IniFile.WriteString('Window', 'WindowState', StateStr);
	finally
		IniFile.Free;
	end;
end;

procedure TfrmMarkdown.FormShow(Sender: TObject);
begin
	if not ParamStr(1).IsEmpty then
	begin
		OpenMarkdown(ParamStr(1));
		OpenDialog1.Filename := ParamStr(1);
	end;
end;

procedure TfrmMarkdown.sbFontBiggerClick(Sender: TObject);
begin
	// increase html scale by 0.1
	FHtmlFontScale := FHtmlFontScale + 0.1;
	if FHtmlFontScale > 3.0 then
		FHtmlFontScale := 3.0;
	// update memo font relative to base 14px
	mmEditor.BeginUpdate;
	mmEditor.StyledSettings := mmEditor.StyledSettings - [TStyledSetting.Size];
	mmEditor.Font.Size := Round(14 * FHtmlFontScale);
	mmEditor.EndUpdate;
	RefreshPreview;
end;

procedure TfrmMarkdown.sbFontSmallClick(Sender: TObject);
begin
	// decrease html scale by 0.1
	FHtmlFontScale := FHtmlFontScale - 0.1;
	if FHtmlFontScale < 0.6 then
		FHtmlFontScale := 0.6;
	mmEditor.BeginUpdate;
	mmEditor.StyledSettings := mmEditor.StyledSettings - [TStyledSetting.Size];
	mmEditor.Font.Size := Round(14 * FHtmlFontScale);
	mmEditor.EndUpdate;
	RefreshPreview;
end;

procedure TfrmMarkdown.RefreshPreview;
var
	html, baseUrl: string;
	AnchorLine: Integer;
begin
	// Build file:/// base URL from the markdown file's directory
	baseUrl := ExtractFilePath(OpenDialog1.Filename);
	if not baseUrl.IsEmpty then
		baseUrl := 'file:///' + StringReplace(baseUrl, '\', '/', [rfReplaceAll]);

	AnchorLine := mmEditor.CaretPosition.Line;
	if AnchorLine < 0 then
		AnchorLine := 0
	else if AnchorLine >= mmEditor.Lines.Count then
		AnchorLine := mmEditor.Lines.Count - 1;

	html := MarkDownToHtml(mmEditor.Lines.Text, baseUrl, AnchorLine);
	if not html.IsEmpty then
	begin
		if mmEditor.Lines.Count > 1 then
			FPendingScrollRatio := AnchorLine / (mmEditor.Lines.Count - 1)
		else
			FPendingScrollRatio := 0;

		FPendingPreviewScroll := true;
		WebBrowser1.LoadFromStrings(html, TEncoding.UTF8, '');
		TFile.WriteAllText('c:\temp\test.html', html, TEncoding.UTF8);
	end;
	mmEditor.SetFocus;
end;

procedure TfrmMarkdown.ApplyMarkdownHeading(const HeadingLevel: Integer);
var
	HeadingMarks: string;
	StartLine, i: Integer;
begin
	// Get current line number where cursor is
	StartLine := mmEditor.CaretPosition.Line;
	if (StartLine < 0) or (StartLine >= mmEditor.Lines.Count) then
		Exit;

	// Build heading marks based on level: 0='#', 1='##', 2='###'
	HeadingMarks := '';
	for i := 0 to HeadingLevel do
		HeadingMarks := HeadingMarks + '#';

	// Remove existing heading marks if any
	if mmEditor.Lines[StartLine].StartsWith('#') then
		mmEditor.Lines[StartLine] := Trim(mmEditor.Lines[StartLine])
	else
		mmEditor.Lines[StartLine] := Trim(mmEditor.Lines[StartLine]);

	// Add heading marks
	mmEditor.Lines[StartLine] := HeadingMarks + ' ' + mmEditor.Lines[StartLine];
	RefreshPreview;
end;

procedure TfrmMarkdown.ApplyCodeBlock;
var
	SelText: string;
	StartPos: TCaretPosition;
begin
	SelText := mmEditor.SelText;
	if SelText.IsEmpty then
		Exit;

	StartPos := mmEditor.CaretPosition;
	mmEditor.DeleteSelection;
	mmEditor.InsertAfter(StartPos, '```' + #13 + SelText + #13 + '```', []);
	RefreshPreview;
end;

procedure TfrmMarkdown.OpenMarkdown(const Filename: string);
begin
	if Filename <> '' then
	begin
		if FileExists(Filename) then
		begin
			mmEditor.Lines.LoadFromFile(Filename);
			FChanged := False;
			RefreshPreview;
			Caption := PROGRAM_NAME + ' - ' + ExtractFileName(Filename);
		end
		else
			ShowMessage('File not found: ' + Filename);
	end;
end;

procedure TfrmMarkdown.sbOpenClick(Sender: TObject);
begin
	if FChanged then
		ConfirmSaved;

	OpenDialog1.Filename := ExtractFileName(OpenDialog1.Filename);
	if OpenDialog1.Execute then
	begin
		self.Caption := PROGRAM_NAME + ' - ' + OpenDialog1.Filename;
		OpenMarkdown(OpenDialog1.Filename);
	end;
end;

procedure TfrmMarkdown.SpeedButton1Click(Sender: TObject);
begin
	mmEditor.UnDo;
end;

procedure TfrmMarkdown.SpeedButton2Click(Sender: TObject);
begin
	RefreshPreview;
end;

procedure TfrmMarkdown.sbItalicClick(Sender: TObject);
begin
	ApplyTextFormat(mmEditor, '_');
end;

procedure TfrmMarkdown.Timer1Timer(Sender: TObject);
begin
	if FKeyPressed then
	begin
		FKeyPressed := False;
		RefreshPreview;
		self.Caption := PROGRAM_NAME + ' - ' + OpenDialog1.Filename;
	end;
end;

procedure TfrmMarkdown.WebBrowser1DidFinishLoad(ASender: TObject);
begin
	if not FPendingPreviewScroll then
		Exit;

	FPendingPreviewScroll := False;
	try
		WebBrowser1.EvaluateJavaScript('var el=document.getElementById("' + PREVIEW_CARET_ANCHOR_ID + '");' + 'if(el){' +
			 'var top=(el.getBoundingClientRect().top + (window.pageYOffset||document.documentElement.scrollTop||document.body.scrollTop||0)) - 120;'
			 + 'if(top<0){top=0;}' + 'window.scrollTo(0, top);' + '}else{' +
			 'var h=Math.max(document.body.scrollHeight, document.documentElement.scrollHeight) - window.innerHeight;' +
			 'if(h<0){h=0;}' + 'window.scrollTo(0, Math.round(h*' + StringReplace(FloatToStr(FPendingScrollRatio), ',', '.',
			 [rfReplaceAll]) + '));' + '}');
	except
		// Keep the editor usable even if a webview engine does not support JS evaluation.
	end;
end;

procedure TfrmMarkdown.sbTitleClick(Sender: TObject);
begin
	{ Tag property usage for sbTitle button:
		0 = '#'    (h1)
		1 = '##'   (h2)
		2 = '###'  (h3)
		3 = '####' (h4)
	}
	ApplyMarkdownHeading((Sender as TSpeedButton).tag);
end;

procedure TfrmMarkdown.sbCodeClick(Sender: TObject);
begin
	ApplyCodeBlock;
end;

procedure TfrmMarkdown.FormActivate(Sender: TObject);
begin
	RefreshPreview;
end;

procedure TfrmMarkdown.FormClose(Sender: TObject; var Action: TCloseAction);
begin
	if FChanged then
		ConfirmSaved;
	SaveWindowState;
end;

procedure TfrmMarkdown.FormCreate(Sender: TObject);
begin
	self.Caption := PROGRAM_NAME;
	mmEditor.StyledSettings := mmEditor.StyledSettings - [TStyledSetting.Size];
	FHtmlFontScale := 1.0;
	FPendingPreviewScroll := False;
	FPendingScrollRatio := 0;
	mmEditor.Font.Size := 14;
	LoadWindowState;
end;

procedure TfrmMarkdown.SaveMarkdown;
var
	localfilename: string;
begin
	localfilename := OpenDialog1.Filename;
  SaveDialog1.InitialDir := ExtractFilePath(localfilename);
	SaveDialog1.Filename := ExtractFileName(localfilename);
	if SaveDialog1.Execute then
		localfilename := SaveDialog1.Filename
	else
		Exit;
	if ExtractFileExt(localfilename).IsEmpty then
		localfilename := localfilename + '.md';

	self.Caption := PROGRAM_NAME + ' - ' + localfilename;
	OpenDialog1.Filename := localfilename;
	mmEditor.Lines.SaveToFile(localfilename, TEncoding.UTF8);
	FChanged := False;
end;

procedure TfrmMarkdown.sbSaveClick(Sender: TObject);
begin
	SaveMarkdown;
end;

procedure TfrmMarkdown.sbStrikeClick(Sender: TObject);
begin
	ApplyTextFormat(mmEditor, '~~');
end;

procedure TfrmMarkdown.ApplyTextFormat(memo: TMemo; TextFormat: string);
var
	SelStartPos, SelLen: Integer;
	SelectedText, FullText: string;
begin
	SelStartPos := memo.SelStart;
	SelLen := memo.SelLength;

	if SelLen <= 0 then
		Exit;

	FullText := memo.Text;
	SelectedText := Copy(FullText, SelStartPos + 1, SelLen);

	// remove is already exists
	if (SelLen >= 4) and SelectedText.StartsWith(TextFormat) and SelectedText.EndsWith(TextFormat) then
	begin
		Delete(FullText, SelStartPos + 1, SelLen);
		Insert(Copy(SelectedText, 3, SelLen - 4), FullText, SelStartPos + 1);
		memo.Text := FullText;

		memo.SelStart := SelStartPos;
		memo.SelLength := SelLen - 4;
	end
	else
	begin
		Delete(FullText, SelStartPos + 1, SelLen);
		Insert(TextFormat + SelectedText + TextFormat, FullText, SelStartPos + 1);
		memo.Text := FullText;

		memo.SelStart := SelStartPos;
		memo.SelLength := SelLen + 4;
  end;

	RefreshPreview;

end;

procedure TfrmMarkdown.sbBoldClick(Sender: TObject);
begin
	ApplyTextFormat(mmEditor, '**');
end;

end.
