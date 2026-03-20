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
	FMX.ImgList, FMX.Menus, System.RegularExpressions;

type
	TfrmMarkdown = class(TForm)
		WebBrowser1: TWebBrowser;
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
		SpeedButton1: TSpeedButton;
		miNew: TMenuItem;
    sbBold: TSpeedButton;
    Panel6: TPanel;
    sbStrike: TSpeedButton;
		sbItalic: TSpeedButton;
    SpeedButton3: TSpeedButton;
    ImageList1: TImageList;
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
		FPreviewInitialized: Boolean;
		FPendingPreviewScroll: Boolean;
		FPendingScrollRatio: Double;
		FPendingInitialLoad: Boolean;
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
		Result := Result + '<base id="sme-base" href="' + baseUrl + '">' + #13
	else
		Result := Result + '<base id="sme-base">' + #13;
	Result := Result + '<style id="sme-style">' + css + '</style>' + #13 +
		 '<script>' +
		 'function smeScrollToAnchor(ratio){' +
		 'var el=document.getElementById("' + PREVIEW_CARET_ANCHOR_ID + '");' +
		 'if(el){' +
		 'var top=(el.getBoundingClientRect().top + (window.pageYOffset||document.documentElement.scrollTop||document.body.scrollTop||0)) - 120;' +
		 'if(top<0){top=0;}' +
		 'window.scrollTo(0, top);' +
		 '}else{' +
		 'var h=Math.max(document.body.scrollHeight, document.documentElement.scrollHeight) - window.innerHeight;' +
		 'if(h<0){h=0;}' +
		 'window.scrollTo(0, Math.round(h*ratio));' +
		 '}' +
		 '}' +
		 'function smeUpdatePreview(css, html, baseHref, ratio){' +
		 'var styleEl=document.getElementById("sme-style");' +
		 'if(styleEl){styleEl.textContent=css;}' +
		 'var baseEl=document.getElementById("sme-base");' +
		 'if(baseEl){if(baseHref){baseEl.setAttribute("href", baseHref);}else{baseEl.removeAttribute("href");}}' +
		 'var root=document.getElementById("sme-preview-root");' +
		 'if(root){root.innerHTML=html;}' +
		 'smeScrollToAnchor(ratio||0);' +
		 '}' +
		 'document.addEventListener("click", function(e) {' +
		 'var t = e.target;' +
		 'while(t && t.tagName !== "A" && t !== document.body) { t = t.parentNode; }' +
		 'if(t && t.tagName === "A") {' +
		 'var href = t.getAttribute("href") || "";' +
		 'if (href.charAt(0) === "#") {' +
		 'e.preventDefault();' +
		 'var id = href.substring(1);' +
		 'var el = document.getElementById(id);' +
		 'if(el) { el.scrollIntoView(true); }' +
		 '}' +
		 '}' +
		 '});' +
		 '</script>' + #13 +
		 '</head>' + #13 + '<body>'#13 +
		 '<div id="sme-preview-root">' + content + '</div>' + #13 +
		 '</body></html>';
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

function AddHeadingAnchors(const Html: string): string;
var
	RegEx: TRegEx;
	Match: TMatch;
	HeadingLevel, HeadingText, AnchorId, Replacement: string;
	LResult: string;
	LastPos: Integer;
begin
	LResult := '';
	LastPos := 1;
	RegEx := TRegEx.Create('<h([1-6])>(.*?)</h\1>', [roIgnoreCase, roSingleLine]);
	Match := RegEx.Match(Html);
	
	while Match.Success do
	begin
		// Copy text before the match
		LResult := LResult + Copy(Html, LastPos, Match.Index - LastPos);
		
		HeadingLevel := Match.Groups[1].Value;
		HeadingText := Match.Groups[2].Value;

		AnchorId := HeadingText.ToLower.Trim;
		AnchorId := TRegEx.Replace(AnchorId, '<.*?>', ''); // strip HTML tags
		AnchorId := TRegEx.Replace(AnchorId, '[^\w\s-]', ''); // remove non-alphanumeric, except spaces and dashes
		AnchorId := StringReplace(AnchorId, ' ', '-', [rfReplaceAll]); // every space becomes a single dash

		Replacement := Format('<h%s id="%s">%s</h%s>', [HeadingLevel, AnchorId, HeadingText, HeadingLevel]);
		LResult := LResult + Replacement;
		
		LastPos := Match.Index + Match.Length;
		Match := Match.NextMatch;
	end;
	
	LResult := LResult + Copy(Html, LastPos, MaxInt);
	Result := LResult;
end;

function MarkDownToBodyHtml(const Input: string; const CaretLine: Integer = -1): String;
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
		html := AddHeadingAnchors(html);
		Result := html;
	finally
		md.Free;
	end;
end;

function MarkDownToHtml(const Input: string; const baseUrl: String = ''; const CaretLine: Integer = -1): String;
var
	bodyHtml: string;
begin
	bodyHtml := MarkDownToBodyHtml(Input, CaretLine);
	if bodyHtml.IsEmpty then
		Exit;
	Result := MakeHTML(LoadCSS(), bodyHtml, baseUrl);
end;

function JavaScriptQuotedString(const Value: string): string;
var
	i: Integer;
	ch: Char;
begin
	Result := '''';
	for i := 1 to Value.Length do
	begin
		ch := Value[i];
		case ch of
			'\': Result := Result + #92#92;
			'''': Result := Result + #92#39;
			#8: Result := Result + #92 + 'b';
			#9: Result := Result + #92 + 't';
			#10: Result := Result + #92 + 'n';
			#12: Result := Result + #92 + 'f';
			#13: Result := Result + #92 + 'r';
		else
			if Ord(ch) < 32 then
				Result := Result + #92 + 'u' + IntToHex(Ord(ch), 4)
			else
				Result := Result + ch;
		end;
	end;
	Result := Result + '''';
end;

function FloatToJavaScript(const Value: Double): string;
begin
	Result := StringReplace(FloatToStr(Value), ',', '.', [rfReplaceAll]);
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
		FPreviewInitialized := False;
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
	if not self.Caption.EndsWith('*') then
		self.Caption := PROGRAM_NAME + ' - ' + OpenDialog1.Filename + '*';

	// Timer-based debounce disabled for now (easy rollback: uncomment lines below).
	// Timer1.Enabled := False;
	// Timer1.Enabled := true;
	RefreshPreview;
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
	 //	OpenMarkdown(ParamStr(1));
		//OpenDialog1.Filename := ParamStr(1);
		FPendingInitialLoad := True;  // Mark that we need a refresh after activation
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
	html, bodyHtml, cssText, baseUrl, updateScript: string;
	AnchorLine: Integer;
begin
	// Don't refresh if memo is empty (e.g., during initial load)
	if (mmEditor.Lines.Count = 0) or ((mmEditor.Lines.Count = 1) and mmEditor.Lines[0].IsEmpty) then
		Exit;

	// Build file:/// base URL from the markdown file's directory
	baseUrl := ExtractFilePath(OpenDialog1.Filename);
	if baseUrl.IsEmpty then
     baseUrl := ExtractFilePath(ParamStr(0));
	if not baseUrl.IsEmpty then
		baseUrl := 'file:///' + StringReplace(baseUrl, '\', '/', [rfReplaceAll]);

	AnchorLine := mmEditor.CaretPosition.Line;
	if AnchorLine < 0 then
		AnchorLine := 0
	else if AnchorLine >= mmEditor.Lines.Count then
		AnchorLine := mmEditor.Lines.Count - 1;

	bodyHtml := MarkDownToBodyHtml(mmEditor.Lines.Text, AnchorLine);
	if not bodyHtml.IsEmpty then
	begin
		cssText := LoadCSS();
		if mmEditor.Lines.Count > 1 then
			FPendingScrollRatio := AnchorLine / (mmEditor.Lines.Count - 1)
		else
			FPendingScrollRatio := 0;

		if not FPreviewInitialized then
		begin
			html := MakeHTML(cssText, bodyHtml, baseUrl);
			FPendingPreviewScroll := true;
			WebBrowser1.LoadFromStrings(html, TEncoding.UTF8, '');
			FPreviewInitialized := True;
		end
		else
		begin
			updateScript := 'if(window.smeUpdatePreview){window.smeUpdatePreview(' +
				 JavaScriptQuotedString(cssText) + ',' +
				 JavaScriptQuotedString(bodyHtml) + ',' +
				 JavaScriptQuotedString(baseUrl) + ',' +
				 FloatToJavaScript(FPendingScrollRatio) + ');}';
			try
				WebBrowser1.EvaluateJavaScript(updateScript);
			except
				// Fallback for webviews that do not allow JS evaluation.
				html := MakeHTML(cssText, bodyHtml, baseUrl);
				FPendingPreviewScroll := true;
				WebBrowser1.LoadFromStrings(html, TEncoding.UTF8, '');
			end;
		end;
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
			FPendingPreviewScroll := False;
			mmEditor.Lines.LoadFromFile(Filename, TEncoding.UTF8);
			// Reset caret to beginning after loading
			mmEditor.CaretPosition := TCaretPosition.Create(0, 0);
			// Reset AFTER loading, so RefreshPreview knows to do full load
			FPreviewInitialized := False;
			RefreshPreview;
			Caption := PROGRAM_NAME + ' - ' + ExtractFileName(Filename);
			FChanged := False;
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

procedure TfrmMarkdown.WebBrowser1DidFinishLoad(ASender: TObject);
begin
	if not FPendingPreviewScroll then
		Exit;

	FPendingPreviewScroll := False;
	try
		WebBrowser1.EvaluateJavaScript('if(window.smeScrollToAnchor){window.smeScrollToAnchor(' + FloatToJavaScript(FPendingScrollRatio) + ');}');
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
	if FPendingInitialLoad then
	begin
		FPendingInitialLoad := False;

		OpenDialog1.Filename := ExtractFileName(ParamStr(1));
		self.Caption := PROGRAM_NAME + ' - ' + OpenDialog1.Filename;
		OpenMarkdown(OpenDialog1.Filename);


	end;
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
	FPreviewInitialized := False;
	FPendingPreviewScroll := False;
	FPendingScrollRatio := 0;
	FPendingInitialLoad := False;
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
