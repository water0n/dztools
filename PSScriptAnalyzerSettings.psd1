@{
    ExcludeRules = @(
        # dztools receives these values from WPF password fields and uses them immediately
        # for SQL/local Windows operations; they are not hard-coded secrets.
        'PSAvoidUsingUsernameAndPasswordParams',
        'PSAvoidUsingConvertToSecureStringWithPlainText'
    )
}
