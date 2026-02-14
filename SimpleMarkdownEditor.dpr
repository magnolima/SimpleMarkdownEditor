program SimpleMarkdownEditor;

uses
  System.StartUpCopy,
  FMX.Forms,
  SimpleMarkdownEditor.gui in 'SimpleMarkdownEditor.gui.pas' {frmMarkdown};

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TfrmMarkdown, frmMarkdown);
  Application.Run;
end.
