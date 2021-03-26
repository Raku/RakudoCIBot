unit class Azure::DevOps;


#OAuth
#https://aex.dev.azure.com/app/register/
#https://docs.microsoft.com/en-us/azure/devops/integrate/get-started/authentication/oauth?view=azure-devops

#create build
#https://docs.microsoft.com/en-us/rest/api/azure/devops/build/builds/queue?view=azure-devops-rest-6.0
#POST https://dev.azure.com/{organization}/{project}/_apis/build/builds?api-version=6.0

#determine jobs
#retrieve status
#https://dev.azure.com/rakudo/rakudo/_apis/build/builds/1036/timeline
#https://docs.microsoft.com/en-us/rest/api/azure/devops/build/timeline/get?view=azure-devops-rest-6.0

#download artifacts
#GET https://dev.azure.com/{organization}/{project}/_apis/build/builds/{buildId}/artifacts?api-version=6.0
